# frozen_string_literal: true

module MongoExplain
  module Monitor
    class Subscriber
      def initialize(queue:, commands_to_explain:, explain_comment:, logger:, deep_copy:, detect_callsite:)
        @queue = queue
        @commands_to_explain = commands_to_explain
        @explain_comment = explain_comment
        @logger = logger
        @deep_copy = deep_copy
        @detect_callsite = detect_callsite
      end

      def started(event)
        command_name = event.command_name.to_s
        return unless @commands_to_explain.include?(command_name)

        original_command = @deep_copy.call(event.command)
        return if original_command["comment"] == @explain_comment

        payload = {
          command_name: command_name,
          database_name: event.database_name.to_s,
          callsite: @detect_callsite.call,
          command: original_command
        }
        @queue.push(payload, true)
      rescue ThreadError
        log_debug("[MongoExplain] queue full; dropping explain probe")
      rescue StandardError => e
        log_debug("[MongoExplain] enqueue failed: #{e.class}: #{e.message}")
      end

      def succeeded(_event); end

      def failed(_event); end

      private

      def log_debug(message)
        current_logger = logger
        return unless current_logger.respond_to?(:debug)

        current_logger.debug(message)
      end

      def logger
        return @logger.call if @logger.respond_to?(:call)

        @logger
      end
    end
  end
end
