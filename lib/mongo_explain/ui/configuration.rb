# frozen_string_literal: true

module MongoExplain
  module Ui
    class Configuration
      attr_accessor :enabled
      attr_accessor :channel_name
      attr_accessor :max_stack
      attr_accessor :default_ttl_ms
      attr_accessor :level_styles

      def initialize
        @enabled = false
        @channel_name = "mongo_explain:ui"
        @max_stack = 5
        @default_ttl_ms = 12_000
        @level_styles = {
          "info" => "mongo-explain-ui-card--info",
          "collscan" => "mongo-explain-ui-card--collscan",
          "warn" => "mongo-explain-ui-card--warn",
          "error" => "mongo-explain-ui-card--error"
        }
      end
    end
  end
end
