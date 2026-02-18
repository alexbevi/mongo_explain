# frozen_string_literal: true

require "spec_helper"

RSpec.describe MongoExplain::Ui::Emitter do
  describe ".emit" do
    it "uses default ttl when ttl_ms is not provided" do
      configuration = double("configuration", default_ttl_ms: 12_000)
      allow(MongoExplain::Ui).to receive(:configuration).and_return(configuration)
      allow(MongoExplain::Ui::Event).to receive(:build).and_return({ id: "event-1" })
      allow(MongoExplain::Ui::Broadcaster).to receive(:broadcast)

      described_class.emit(title: "T", message: "M")

      expect(MongoExplain::Ui::Event).to have_received(:build).with(
        hash_including(title: "T", message: "M", ttl_ms: 12_000, level: "info")
      )
      expect(MongoExplain::Ui::Broadcaster).to have_received(:broadcast).with({ id: "event-1" })
    end
  end

  describe ".emit_explain_summary" do
    it "emits collscan level payloads with elevated ttl" do
      allow(described_class).to receive(:emit)

      described_class.emit_explain_summary(
        callsite: "app/models/team.rb:12",
        operation: "find",
        namespace: "treasurer.teams",
        plan: "IXSCAN>COLLSCAN",
        index: "team_id_1",
        docs_examined: 30,
        keys_examined: 10,
        execution_ms: 5,
        collscan: true,
        unknown_plan: false
      )

      expect(described_class).to have_received(:emit).with(
        hash_including(
          title: "MongoExplain FIND",
          level: "collscan",
          ttl_ms: 20_000,
          dedupe_key: "app/models/team.rb:12:find:treasurer.teams:IXSCAN>COLLSCAN",
          meta: hash_including(index: "team_id_1")
        )
      )
    end

    it "emits warn level payloads when plan is unknown" do
      allow(described_class).to receive(:emit)

      described_class.emit_explain_summary(
        callsite: "app/models/team.rb:12",
        operation: "aggregate",
        namespace: "treasurer.teams",
        plan: "UNKNOWN",
        index: "-",
        docs_examined: "-",
        keys_examined: "-",
        execution_ms: "-",
        collscan: false,
        unknown_plan: true
      )

      expect(described_class).to have_received(:emit).with(
        hash_including(level: "warn", ttl_ms: 20_000)
      )
    end

    it "emits info level payloads for normal plans" do
      allow(described_class).to receive(:emit)

      described_class.emit_explain_summary(
        callsite: "app/models/team.rb:12",
        operation: "find",
        namespace: "treasurer.teams",
        plan: "IXSCAN",
        index: "team_id_1",
        docs_examined: 1,
        keys_examined: 1,
        execution_ms: 0,
        collscan: false,
        unknown_plan: false
      )

      expect(described_class).to have_received(:emit).with(
        hash_including(level: "info", ttl_ms: 10_000)
      )
    end
  end
end
