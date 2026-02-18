# frozen_string_literal: true

require "json"
require "logger"
require "bson"

module MongoExplain
  module DevelopmentMonitor
    extend self

    COMMANDS_TO_EXPLAIN = %w[find aggregate count distinct].freeze
    INTERNAL_COMMAND_KEYS = %w[
      $db
      lsid
      $clusterTime
      $readPreference
      readConcern
      writeConcern
      txnNumber
      autocommit
      startTransaction
    ].freeze
    WORKER_QUEUE_SIZE = 200
    WORKER_COUNT = 1
    LOG_ONLY_COLLSCAN = ENV["MONGO_EXPLAIN_ONLY_COLLSCAN"] == "1"
    EXPLAIN_COMMENT = "__development_explain_probe__".freeze
    GREEN = "\e[32m".freeze
    RESET = "\e[0m".freeze
    STOP_SIGNAL = Object.new
    STACK_DEPTH = 80
    SKIPPED_CALLSITE_FILES = %w[
      config/initializers/mongoid.rb
      lib/mongo_explain/development_monitor.rb
    ].freeze

    class Subscriber
      def initialize(queue)
        @queue = queue
      end

      def started(event)
        command_name = event.command_name.to_s
        return unless COMMANDS_TO_EXPLAIN.include?(command_name)

        original_command = DevelopmentMonitor.deep_copy(event.command)
        return if original_command["comment"] == EXPLAIN_COMMENT

        payload = {
          command_name: command_name,
          database_name: event.database_name.to_s,
          callsite: DevelopmentMonitor.detect_callsite,
          command: original_command
        }
        @queue.push(payload, true)
      rescue ThreadError
        DevelopmentMonitor.logger.debug("[MongoExplain] queue full; dropping explain probe")
      rescue StandardError => e
        DevelopmentMonitor.logger.debug("[MongoExplain] enqueue failed: #{e.class}: #{e.message}")
      end

      def succeeded(_event); end

      def failed(_event); end
    end

    def install!
      return unless enabled?
      return if @installed

      @queue = SizedQueue.new(WORKER_QUEUE_SIZE)
      @workers = Array.new(WORKER_COUNT) { spawn_worker }
      @subscriber = Subscriber.new(@queue)
      Mongo::Monitoring::Global.subscribe(Mongo::Monitoring::COMMAND, @subscriber)
      at_exit { shutdown! }
      @installed = true
      logger.info("[MongoExplain] development explain monitor enabled")
    end

    def shutdown!
      return unless @installed

      WORKER_COUNT.times { @queue.push(STOP_SIGNAL) rescue nil }
      @workers.each { |worker| worker.join(0.5) }
      @installed = false
    end

    def spawn_worker
      Thread.new do
        Thread.current.name = "mongo-explain-monitor" if Thread.current.respond_to?(:name=)
        loop do
          payload = @queue.pop
          break if payload.equal?(STOP_SIGNAL)

          process_payload(payload)
        rescue StandardError => e
          logger.debug("[MongoExplain] worker loop error: #{e.class}: #{e.message}")
        end
      end
    end

    def process_payload(payload)
      command_name = payload[:command_name]
      explain_target = explain_target_for(command_name, payload[:command])
      return if explain_target.nil?

      explain_result = run_explain(payload[:database_name], explain_target)
      winning_plan = winning_plan_for(explain_result)
      return if LOG_ONLY_COLLSCAN && !collscan_plan?(winning_plan)
      execution_stats = execution_stats_for(explain_result)
      collscan = collscan_plan?(winning_plan)
      plan_path = plan_stage_path(winning_plan)
      unknown_plan = plan_path == "UNKNOWN"

      logger.info(
        colorize(
          "[MongoExplain] callsite=#{payload[:callsite]} op=#{command_name} " \
          "ns=#{namespace_for(explain_result, payload[:database_name], explain_target, command_name)} " \
          "plan=#{plan_path} " \
          "index=#{index_names_for(winning_plan)} " \
          "returned=#{stat_value(execution_stats, "nReturned")} " \
          "docs=#{stat_value(execution_stats, "totalDocsExamined")} " \
          "keys=#{stat_value(execution_stats, "totalKeysExamined")} " \
          "ms=#{stat_value(execution_stats, "executionTimeMillis")}"
        )
      )

      if defined?(MongoExplain::Ui::Emitter)
        MongoExplain::Ui::Emitter.emit_explain_summary(
          callsite: payload[:callsite],
          operation: command_name,
          namespace: namespace_for(explain_result, payload[:database_name], explain_target, command_name),
          plan: plan_path,
          index: index_names_for(winning_plan),
          docs_examined: stat_value(execution_stats, "totalDocsExamined"),
          keys_examined: stat_value(execution_stats, "totalKeysExamined"),
          execution_ms: stat_value(execution_stats, "executionTimeMillis"),
          collscan: collscan,
          unknown_plan: unknown_plan
        )
      end

      return unless collscan || unknown_plan

      logger.info(
        colorize(
          "[MongoExplainDetails] callsite=#{payload[:callsite]} op=#{command_name} " \
          "command=#{to_json(explain_target)} " \
          "winning_plan=#{to_json(winning_plan)} " \
          "execution_stats=#{to_json(execution_stats)}"
        )
      )
    rescue StandardError => e
      logger.debug(
        colorize(
          "[MongoExplain] callsite=#{payload[:callsite]} command=#{payload[:command_name]} " \
          "explain_error=#{e.class}: #{e.message}"
        )
      )
    end

    def run_explain(database_name, explain_target)
      command = {
        "explain" => explain_target,
        "verbosity" => "executionStats",
        "comment" => EXPLAIN_COMMENT
      }
      result = Mongoid.default_client.use(database_name).database.command(command)
      if result.respond_to?(:documents)
        result.documents.first || {}
      elsif result.respond_to?(:first)
        result.first || {}
      else
        result || {}
      end
    end

    def explain_target_for(command_name, command)
      return nil unless command[command_name]

      command.each_with_object({}) do |(key, value), explain_target|
        next if INTERNAL_COMMAND_KEYS.include?(key.to_s)
        next if key.to_s == "comment"

        explain_target[key.to_s] = value
      end
    end

    def detect_callsite
      root_prefix = rails_root_prefix
      return "unknown" if blank_value?(root_prefix)

      caller_locations(3, STACK_DEPTH).each do |location|
        absolute = location.absolute_path || location.path
        next if blank_value?(absolute)
        next unless absolute.start_with?(root_prefix)

        relative = absolute.delete_prefix(root_prefix)
        next unless relative.start_with?("app/", "lib/")
        next if SKIPPED_CALLSITE_FILES.include?(relative)

        return "#{relative}:#{location.lineno}"
      end
      "unknown"
    end

    def winning_plan_for(document)
      query_planner = query_planner_for(document)
      return nil unless query_planner.is_a?(Hash) || query_planner.is_a?(BSON::Document)

      query_planner["winningPlan"]
    end

    def execution_stats_for(document)
      stats = document["executionStats"]
      unless stats.is_a?(Hash) || stats.is_a?(BSON::Document)
        cursor_stage = cursor_stage_for(document)
        stats = cursor_stage&.dig("$cursor", "executionStats")
      end
      return {} unless stats.is_a?(Hash) || stats.is_a?(BSON::Document)

      stats
    end

    def namespace_for(document, database_name, explain_target, command_name)
      query_planner = query_planner_for(document)
      if query_planner.is_a?(Hash) || query_planner.is_a?(BSON::Document)
        namespace = query_planner["namespace"].to_s
        return namespace if present_value?(namespace)
      end

      collection_name = explain_target[command_name].to_s
      return "unknown" if blank_value?(collection_name)

      "#{database_name}.#{collection_name}"
    end

    def plan_stage_path(plan)
      stages = stage_names_from(plan)
      return "UNKNOWN" if stages.empty?

      stages.join(">")
    end

    def query_planner_for(document)
      query_planner = document["queryPlanner"]
      if query_planner.is_a?(Hash) || query_planner.is_a?(BSON::Document)
        return query_planner
      end

      cursor_stage = cursor_stage_for(document)
      query_planner = cursor_stage&.dig("$cursor", "queryPlanner")
      return query_planner if query_planner.is_a?(Hash) || query_planner.is_a?(BSON::Document)

      nil
    end

    def cursor_stage_for(document)
      stages = document["stages"]
      return nil unless stages.is_a?(Array)

      stages.find do |stage|
        (stage.is_a?(Hash) || stage.is_a?(BSON::Document)) &&
          (stage["$cursor"].is_a?(Hash) || stage["$cursor"].is_a?(BSON::Document))
      end
    end

    def stage_names_from(node)
      case node
      when Hash, BSON::Document
        current_stage = node["stage"].to_s
        nested =
          node["inputStage"] ||
          node["outerStage"] ||
          node["innerStage"] ||
          node["queryPlan"]

        stages = present_value?(current_stage) ? [ current_stage ] : []
        return stages + stage_names_from(nested) if nested

        if node["inputStages"].is_a?(Array)
          branch_stages = node["inputStages"].flat_map { |child| stage_names_from(child) }
          return stages + branch_stages
        end

        if node["shards"].is_a?(Array)
          shard_stages = node["shards"].flat_map do |shard|
            shard_plan = shard["winningPlan"] || shard["executionStages"]
            stage_names_from(shard_plan)
          end
          return stages + shard_stages
        end

        stages
      when Array
        node.flat_map { |child| stage_names_from(child) }
      else
        []
      end
    end

    def index_names_for(plan)
      names = gather_index_names(plan).uniq
      return "-" if names.empty?

      names.join(",")
    end

    def gather_index_names(node)
      case node
      when Hash, BSON::Document
        names = []
        index_name = node["indexName"].to_s
        names << index_name if present_value?(index_name)

        node.each_value do |nested|
          names.concat(gather_index_names(nested))
        end
        names
      when Array
        node.flat_map { |nested| gather_index_names(nested) }
      else
        []
      end
    end

    def stat_value(stats, key)
      value = stats[key]
      return "-" if value.nil?

      value
    end

    def collscan_plan?(plan)
      case plan
      when Hash, BSON::Document
        return true if plan["stage"] == "COLLSCAN"

        plan.any? { |_key, nested| collscan_plan?(nested) }
      when Array
        plan.any? { |nested| collscan_plan?(nested) }
      else
        false
      end
    end

    def deep_copy(value)
      case value
      when Hash, BSON::Document
        value.each_with_object({}) do |(key, nested), copied|
          copied[key.to_s] = deep_copy(nested)
        end
      when Array
        value.map { |nested| deep_copy(nested) }
      else
        value
      end
    end

    def to_json(value)
      JSON.generate(json_safe(value))
    end

    def json_safe(value)
      case value
      when Hash, BSON::Document
        value.each_with_object({}) do |(key, nested), converted|
          converted[key.to_s] = json_safe(nested)
        end
      when Array
        value.map { |nested| json_safe(nested) }
      when Symbol
        value.to_s
      when BSON::ObjectId
        value.to_s
      when BigDecimal
        value.to_s("F")
      when Time
        value.iso8601(6)
      when Date, DateTime
        value.iso8601
      else
        value
      end
    end

    def colorize(message)
      return message unless $stdout.tty?
      return message if present_value?(ENV["NO_COLOR"])

      "#{GREEN}#{message}#{RESET}"
    end

    def enabled?
      development_mode? &&
        ENV["MONGO_EXPLAIN"] == "1" &&
        defined?(Mongo::Monitoring::Global) &&
        defined?(Mongo::Monitoring::COMMAND)
    end

    def logger
      return Rails.logger if rails_loaded? && Rails.respond_to?(:logger) && Rails.logger

      @logger ||= Logger.new($stdout).tap do |fallback_logger|
        fallback_logger.progname = "MongoExplain"
      end
    end

    def development_mode?
      return Rails.env.development? if rails_loaded? && Rails.respond_to?(:env)

      true
    end

    def rails_root_prefix
      return nil unless rails_loaded? && Rails.respond_to?(:root) && Rails.root

      "#{Rails.root}/"
    end

    def rails_loaded?
      defined?(Rails)
    end

    def blank_value?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def present_value?(value)
      !blank_value?(value)
    end
  end
end
