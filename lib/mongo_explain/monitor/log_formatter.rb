# frozen_string_literal: true

require "json"
require "bson"
require "date"
require "time"
require "bigdecimal"

module MongoExplain
  module Monitor
    class LogFormatter
      GREEN = "\e[32m".freeze
      RESET = "\e[0m".freeze

      def initialize(color_enabled: nil)
        @color_enabled = color_enabled || method(:default_color_enabled?)
      end

      def summary(callsite:, operation:, namespace:, plan:, index:, returned:, docs:, keys:, ms:)
        colorize(
          "[MongoExplain] callsite=#{callsite} op=#{operation} " \
          "ns=#{namespace} " \
          "plan=#{plan} " \
          "index=#{index} " \
          "returned=#{returned} " \
          "docs=#{docs} " \
          "keys=#{keys} " \
          "ms=#{ms}"
        )
      end

      def details(callsite:, operation:, command:, winning_plan:, execution_stats:)
        colorize(
          "[MongoExplainDetails] callsite=#{callsite} op=#{operation} " \
          "command=#{to_json(command)} " \
          "winning_plan=#{to_json(winning_plan)} " \
          "execution_stats=#{to_json(execution_stats)}"
        )
      end

      def explain_error(callsite:, command:, error:)
        colorize(
          "[MongoExplain] callsite=#{callsite} command=#{command} " \
          "explain_error=#{error.class}: #{error.message}"
        )
      end

      private

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
        return message unless @color_enabled.call

        "#{GREEN}#{message}#{RESET}"
      end

      def default_color_enabled?
        $stdout.tty? && !present_value?(ENV["NO_COLOR"])
      end

      def present_value?(value)
        !blank_value?(value)
      end

      def blank_value?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
