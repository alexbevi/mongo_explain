# frozen_string_literal: true

module MongoExplain
  module Ui
    module OverlayHelper
      def mongo_explain_overlay_enabled?
        return false unless user_signed_in?

        MongoExplain::Ui.configuration.enabled
      end

      def mongo_explain_overlay_channel_name
        MongoExplain::Ui.configuration.channel_name
      end

      def mongo_explain_overlay_max_stack
        MongoExplain::Ui.configuration.max_stack
      end

      def mongo_explain_overlay_default_ttl_ms
        MongoExplain::Ui.configuration.default_ttl_ms
      end
    end
  end
end
