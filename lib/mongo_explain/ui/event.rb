# frozen_string_literal: true

require "securerandom"

module MongoExplain
  module Ui
    class Event
      MAX_STRING_LENGTH = 500

      def self.build(title:, message:, level: "info", ttl_ms: nil, dismissible: true, dedupe_key: nil, meta: {})
        event_id = "#{Time.current.to_f}-#{SecureRandom.hex(4)}"

        {
          id: event_id,
          title: truncate(title),
          message: truncate(message),
          level: level.to_s,
          ttl_ms: ttl_ms,
          dismissible: dismissible,
          dedupe_key: dedupe_key,
          created_at: Time.current.iso8601(6),
          meta: sanitize_meta(meta)
        }
      end

      def self.truncate(value)
        value.to_s.tr("\n", " ")[0...MAX_STRING_LENGTH]
      end

      def self.sanitize_meta(meta)
        return {} unless meta.respond_to?(:to_h)

        meta.to_h.each_with_object({}) do |(key, value), sanitized|
          sanitized[key.to_s] = truncate(value)
        end
      end

      private_class_method :truncate, :sanitize_meta
    end
  end
end
