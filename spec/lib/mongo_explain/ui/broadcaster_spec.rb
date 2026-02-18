# frozen_string_literal: true

require "spec_helper"

RSpec.describe MongoExplain::Ui::Broadcaster do
  let(:configuration) { double("configuration", enabled: enabled, channel_name: "mongo_explain:test") }
  let(:server) { double("action_cable_server") }

  before do
    allow(MongoExplain::Ui).to receive(:configuration).and_return(configuration)
    allow(server).to receive(:broadcast)
  end

  context "when disabled" do
    let(:enabled) { false }

    it "does not broadcast" do
      action_cable = Module.new
      srv = server
      action_cable.define_singleton_method(:server) { srv }
      stub_const("ActionCable", action_cable)

      described_class.broadcast({ title: "x" })

      expect(server).not_to have_received(:broadcast)
    end
  end

  context "when enabled" do
    let(:enabled) { true }

    it "broadcasts hash payloads as-is" do
      action_cable = Module.new
      srv = server
      action_cable.define_singleton_method(:server) { srv }
      stub_const("ActionCable", action_cable)

      payload = { title: "MongoExplain" }
      described_class.broadcast(payload)

      expect(server).to have_received(:broadcast).with("mongo_explain:test", payload)
    end

    it "normalizes non-hash payloads to an empty hash" do
      action_cable = Module.new
      srv = server
      action_cable.define_singleton_method(:server) { srv }
      stub_const("ActionCable", action_cable)

      described_class.broadcast("not a hash")

      expect(server).to have_received(:broadcast).with("mongo_explain:test", {})
    end

    it "logs debug when broadcasting fails" do
      logger = double("rails_logger", debug: nil)
      rails = Module.new
      rails.define_singleton_method(:logger) { logger }
      stub_const("Rails", rails)

      failing_server = double("action_cable_server")
      allow(failing_server).to receive(:broadcast).and_raise(StandardError.new("boom"))
      action_cable = Module.new
      action_cable.define_singleton_method(:server) { failing_server }
      stub_const("ActionCable", action_cable)

      described_class.broadcast({ title: "MongoExplain" })

      expect(logger).to have_received(:debug).with("[MongoExplain::Ui] broadcast failed: StandardError: boom")
    end
  end
end
