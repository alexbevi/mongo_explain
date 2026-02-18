# frozen_string_literal: true

module MongoExplain
  module Ui
    class Channel < ActionCable::Channel::Base
      def subscribed
        reject unless MongoExplain::Ui.configuration.enabled

        stream_from(MongoExplain::Ui.configuration.channel_name)
      end
    end
  end
end
