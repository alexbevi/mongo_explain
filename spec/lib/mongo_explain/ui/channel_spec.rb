# frozen_string_literal: true

require "spec_helper"

unless defined?(ActionCable)
  module ActionCable
    module Channel
      class Base
        def reject; end

        def stream_from(_channel_name); end
      end
    end
  end
end

require_relative "../../../../lib/mongo_explain/ui/channel"

RSpec.describe MongoExplain::Ui::Channel do
  let(:configuration) { double("configuration", enabled: enabled, channel_name: "mongo_explain:test") }

  before do
    allow(MongoExplain::Ui).to receive(:configuration).and_return(configuration)
  end

  context "when ui is disabled" do
    let(:enabled) { false }

    it "rejects the subscription" do
      channel = described_class.new
      allow(channel).to receive(:reject)
      allow(channel).to receive(:stream_from)

      channel.subscribed

      expect(channel).to have_received(:reject)
    end
  end

  context "when ui is enabled" do
    let(:enabled) { true }

    it "streams from configured channel" do
      channel = described_class.new
      allow(channel).to receive(:reject)
      allow(channel).to receive(:stream_from)

      channel.subscribed

      expect(channel).to have_received(:stream_from).with("mongo_explain:test")
    end
  end
end
