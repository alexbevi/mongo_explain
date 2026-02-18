# frozen_string_literal: true

require_relative "development_monitor"
require_relative "ui/configuration"
require_relative "ui/event"
require_relative "ui/broadcaster"
require_relative "ui/emitter"

if defined?(Rails::Engine)
  require_relative "ui/engine"
end

module MongoExplain
  module Ui
    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end
    end
  end
end
