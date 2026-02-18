# frozen_string_literal: true

require "spec_helper"

RSpec.describe MongoExplain::Ui::Event do
  before do
    next if Time.respond_to?(:current)

    Time.singleton_class.class_eval do
      define_method(:current) { now }
    end
    @defined_time_current = true
  end

  after do
    next unless @defined_time_current

    Time.singleton_class.class_eval do
      remove_method(:current)
    end
  end

  it "builds an event with normalized fields" do
    fixed = Time.utc(2025, 1, 1, 10, 0, 0)
    allow(Time).to receive(:current).and_return(fixed)
    allow(SecureRandom).to receive(:hex).with(4).and_return("a1b2c3d4")

    event = described_class.build(
      title: "Mongo\nTitle",
      message: "Query\nmessage",
      level: :warn,
      ttl_ms: 1000,
      dismissible: false,
      dedupe_key: "k1",
      meta: { callsite: "app/models/team.rb:12" }
    )

    expect(event[:id]).to eq("1735725600.0-a1b2c3d4")
    expect(event[:title]).to eq("Mongo Title")
    expect(event[:message]).to eq("Query message")
    expect(event[:level]).to eq("warn")
    expect(event[:ttl_ms]).to eq(1000)
    expect(event[:dismissible]).to eq(false)
    expect(event[:dedupe_key]).to eq("k1")
    expect(event[:created_at]).to eq("2025-01-01T10:00:00.000000Z")
    expect(event[:meta]).to eq({ "callsite" => "app/models/team.rb:12" })
  end

  it "truncates title/message and meta values to max length" do
    long = "x" * 800

    event = described_class.build(
      title: long,
      message: long,
      meta: { long: long }
    )

    expect(event[:title].length).to eq(described_class::MAX_STRING_LENGTH)
    expect(event[:message].length).to eq(described_class::MAX_STRING_LENGTH)
    expect(event[:meta]["long"].length).to eq(described_class::MAX_STRING_LENGTH)
  end

  it "returns empty meta when object cannot be converted to a hash" do
    event = described_class.build(
      title: "t",
      message: "m",
      meta: Object.new
    )

    expect(event[:meta]).to eq({})
  end
end
