# frozen_string_literal: true

require "spec_helper"

RSpec.describe MongoExplain::Monitor::Subscriber do
  let(:queue) { instance_double(SizedQueue) }
  let(:logger) { double("logger", debug: nil) }
  let(:deep_copy) { ->(value) { Marshal.load(Marshal.dump(value)) } }
  let(:detect_callsite) { -> { "app/models/team.rb:12" } }

  subject(:subscriber) do
    described_class.new(
      queue: queue,
      commands_to_explain: %w[find aggregate],
      explain_comment: "__probe__",
      logger: logger,
      deep_copy: deep_copy,
      detect_callsite: detect_callsite
    )
  end

  it "enqueues explainable command payloads" do
    event = double(
      "event",
      command_name: "find",
      database_name: "treasurer",
      command: { "find" => "teams", "filter" => { "name" => "A" } }
    )

    expect(queue).to receive(:push).with(
      {
        command_name: "find",
        database_name: "treasurer",
        callsite: "app/models/team.rb:12",
        command: { "find" => "teams", "filter" => { "name" => "A" } }
      },
      true
    )

    subscriber.started(event)
  end

  it "skips commands that use the internal explain marker" do
    event = double(
      "event",
      command_name: "find",
      database_name: "treasurer",
      command: { "find" => "teams", "comment" => "__probe__" }
    )

    expect(queue).not_to receive(:push)

    subscriber.started(event)
  end

  it "logs and drops payloads when the worker queue is full" do
    event = double(
      "event",
      command_name: "aggregate",
      database_name: "treasurer",
      command: { "aggregate" => "teams" }
    )

    allow(queue).to receive(:push).and_raise(ThreadError)

    expect(logger).to receive(:debug).with("[MongoExplain] queue full; dropping explain probe")

    subscriber.started(event)
  end
end
