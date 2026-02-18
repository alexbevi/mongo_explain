# frozen_string_literal: true

module MongoExplain
  module Ui
    module Broadcaster
      module_function

      def broadcast(event_payload)
        return unless enabled?

        ActionCable.server.broadcast(channel_name, normalized_payload(event_payload))
      rescue StandardError => e
        Rails.logger.debug("[MongoExplain::Ui] broadcast failed: #{e.class}: #{e.message}")
      end

      def enabled?
        MongoExplain::Ui.configuration.enabled
      end

      def channel_name
        MongoExplain::Ui.configuration.channel_name
      end

      def normalized_payload(event_payload)
        return event_payload if event_payload.is_a?(Hash)

        {}
      end
      private_class_method :normalized_payload
    end
  end
end
