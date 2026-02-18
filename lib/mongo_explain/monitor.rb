# frozen_string_literal: true

begin
  require "logger"
rescue LoadError
  # Logger may be unavailable in environments where stdlib default gems are not installed.
end
require "bson"

require_relative "monitor/subscriber"
require_relative "monitor/log_formatter"

module MongoExplain
  module Monitor
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
    STOP_SIGNAL = Object.new
    STACK_DEPTH = 80
    SKIPPED_CALLSITE_FILES = %w[
      config/initializers/mongoid.rb
      lib/mongo_explain/monitor.rb
    ].freeze
    class BasicLogger
      def initialize(io, progname: nil)
        @io = io
        @progname = progname
      end

      attr_accessor :progname

      def info(message)
        write("INFO", message)
      end

      def debug(message)
        write("DEBUG", message)
      end

      private

      def write(level, message)
        prefix = progname ? "#{progname} " : ""
        @io.puts("[#{prefix}#{level}] #{message}")
      end
    end

    def configure
      yield(self)
    end

    def client_provider=(provider)
      @client_provider = provider
    end

    def logger=(custom_logger)
      @logger = custom_logger
    end

    def install!
      return unless enabled?
      return if @installed

      @queue = SizedQueue.new(WORKER_QUEUE_SIZE)
      @workers = Array.new(WORKER_COUNT) { spawn_worker }
      @subscriber = build_subscriber
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
      return if explain_result.nil?

      winning_plan = winning_plan_for(explain_result)
      return if LOG_ONLY_COLLSCAN && !collscan_plan?(winning_plan)

      execution_stats = execution_stats_for(explain_result)
      collscan = collscan_plan?(winning_plan)
      plan_path = plan_stage_path(winning_plan)
      unknown_plan = plan_path == "UNKNOWN"
      namespace = namespace_for(explain_result, payload[:database_name], explain_target, command_name)
      index_names = index_names_for(winning_plan)
      docs_examined = stat_value(execution_stats, "totalDocsExamined")
      keys_examined = stat_value(execution_stats, "totalKeysExamined")
      execution_ms = stat_value(execution_stats, "executionTimeMillis")

      logger.info(
        formatter.summary(
          callsite: payload[:callsite],
          operation: command_name,
          namespace: namespace,
          plan: plan_path,
          index: index_names,
          returned: stat_value(execution_stats, "nReturned"),
          docs: docs_examined,
          keys: keys_examined,
          ms: execution_ms
        )
      )

      if defined?(MongoExplain::Ui::Emitter)
        MongoExplain::Ui::Emitter.emit_explain_summary(
          callsite: payload[:callsite],
          operation: command_name,
          namespace: namespace,
          plan: plan_path,
          index: index_names,
          docs_examined: docs_examined,
          keys_examined: keys_examined,
          execution_ms: execution_ms,
          collscan: collscan,
          unknown_plan: unknown_plan
        )
      end

      return unless collscan || unknown_plan

      logger.info(
        formatter.details(
          callsite: payload[:callsite],
          operation: command_name,
          command: explain_target,
          winning_plan: winning_plan,
          execution_stats: execution_stats
        )
      )
    rescue StandardError => e
      logger.debug(
        formatter.explain_error(
          callsite: payload[:callsite],
          command: payload[:command_name],
          error: e
        )
      )
    end

    def run_explain(database_name, explain_target)
      client = explain_client
      return nil if client.nil?

      command = {
        "explain" => explain_target,
        "verbosity" => "executionStats",
        "comment" => EXPLAIN_COMMENT
      }

      selected_client =
        if present_value?(database_name) && client.respond_to?(:use)
          client.use(database_name)
        else
          client
        end
      return nil unless selected_client.respond_to?(:database)

      database = selected_client.database
      return nil unless database.respond_to?(:command)

      result = database.command(command)
      if result.respond_to?(:documents)
        result.documents.first || {}
      elsif result.respond_to?(:first)
        result.first || {}
      else
        result || {}
      end
    rescue StandardError => e
      logger.debug("[MongoExplain] explain command failed: #{e.class}: #{e.message}")
      nil
    end

    def explain_client
      provider = client_provider
      return nil unless provider.respond_to?(:call)

      provider.call
    rescue StandardError => e
      logger.debug("[MongoExplain] client provider failed: #{e.class}: #{e.message}")
      nil
    end

    def client_provider
      return @client_provider if defined?(@client_provider)

      @client_provider = default_client_provider
    end

    def default_client_provider
      return nil unless defined?(Mongoid) && Mongoid.respond_to?(:default_client)

      proc { Mongoid.default_client }
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

        stages = present_value?(current_stage) ? [current_stage] : []
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

    def enabled?
      development_mode? &&
        ENV["MONGO_EXPLAIN"] == "1" &&
        defined?(Mongo::Monitoring::Global) &&
        defined?(Mongo::Monitoring::COMMAND) &&
        explain_client_configured?
    end

    def explain_client_configured?
      client_provider.respond_to?(:call)
    end

    def logger
      return Rails.logger if rails_loaded? && Rails.respond_to?(:logger) && Rails.logger

      @logger ||= begin
        if defined?(::Logger)
          ::Logger.new($stdout).tap do |fallback_logger|
            fallback_logger.progname = "MongoExplain"
          end
        else
          BasicLogger.new($stdout, progname: "MongoExplain")
        end
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

    private

    def build_subscriber
      Subscriber.new(
        queue: @queue,
        commands_to_explain: COMMANDS_TO_EXPLAIN,
        explain_comment: EXPLAIN_COMMENT,
        logger: -> { logger },
        deep_copy: method(:deep_copy),
        detect_callsite: method(:detect_callsite)
      )
    end

    def formatter
      @formatter ||= LogFormatter.new
    end
  end

end
