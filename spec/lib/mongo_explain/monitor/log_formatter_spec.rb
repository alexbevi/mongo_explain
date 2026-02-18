# frozen_string_literal: true

require "spec_helper"

RSpec.describe MongoExplain::Monitor::LogFormatter do
  describe "#summary" do
    it "formats the monitor summary line" do
      formatter = described_class.new(color_enabled: -> { false })

      line = formatter.summary(
        callsite: "app/models/team.rb:12",
        operation: "find",
        namespace: "treasurer.teams",
        plan: "IXSCAN",
        index: "team_id_1",
        returned: 1,
        docs: 1,
        keys: 1,
        ms: 0
      )

      expect(line).to eq(
        "[MongoExplain] callsite=app/models/team.rb:12 op=find " \
        "ns=treasurer.teams plan=IXSCAN index=team_id_1 returned=1 docs=1 keys=1 ms=0"
      )
    end
  end

  describe "#details" do
    it "serializes bson/object/time values for detail logs" do
      formatter = described_class.new(color_enabled: -> { false })
      object_id = BSON::ObjectId.new

      line = formatter.details(
        callsite: "app/models/team.rb:12",
        operation: "aggregate",
        command: {
          "aggregate" => "teams",
          "id" => object_id,
          "amount" => BigDecimal("12.5"),
          "at" => Time.utc(2025, 1, 1, 12, 30, 45, 123_456)
        },
        winning_plan: { "stage" => "COLLSCAN" },
        execution_stats: { "nReturned" => 2 }
      )

      expect(line).to include("[MongoExplainDetails] callsite=app/models/team.rb:12 op=aggregate")
      expect(line).to include("\"id\":\"#{object_id}\"")
      expect(line).to include("\"amount\":\"12.5\"")
      expect(line).to include("\"at\":\"2025-01-01T12:30:45.123456Z\"")
    end
  end

  describe "colorized output" do
    it "wraps lines when color output is enabled" do
      formatter = described_class.new(color_enabled: -> { true })

      line = formatter.summary(
        callsite: "app/models/team.rb:12",
        operation: "find",
        namespace: "treasurer.teams",
        plan: "IXSCAN",
        index: "team_id_1",
        returned: 1,
        docs: 1,
        keys: 1,
        ms: 0
      )

      expect(line).to start_with("\e[32m")
      expect(line).to end_with("\e[0m")
    end
  end
end
