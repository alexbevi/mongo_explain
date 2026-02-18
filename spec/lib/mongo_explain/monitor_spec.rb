# frozen_string_literal: true

require "spec_helper"

RSpec.describe MongoExplain::Monitor do
  let(:aggregate_explain_result) do
    {
      "stages" => [
        {
          "$cursor" => {
            "queryPlanner" => {
              "namespace" => "treasurer.teams",
              "winningPlan" => {
                "stage" => "SORT",
                "inputStage" => {
                  "stage" => "COLLSCAN"
                }
              }
            },
            "executionStats" => {
              "nReturned" => 7,
              "executionTimeMillis" => 0,
              "totalKeysExamined" => 0,
              "totalDocsExamined" => 7
            }
          }
        },
        {
          "$facet" => {
            "records" => [],
            "total_count" => []
          }
        }
      ]
    }
  end

  it "extracts winning plan from aggregate cursor stage explains" do
    winning_plan = described_class.winning_plan_for(aggregate_explain_result)

    expect(winning_plan).not_to be_nil
    expect(described_class.plan_stage_path(winning_plan)).to eq("SORT>COLLSCAN")
  end

  it "extracts execution stats from aggregate cursor stage explains" do
    stats = described_class.execution_stats_for(aggregate_explain_result)

    expect(stats["nReturned"]).to eq(7)
    expect(stats["totalDocsExamined"]).to eq(7)
    expect(stats["totalKeysExamined"]).to eq(0)
    expect(stats["executionTimeMillis"]).to eq(0)
  end

  it "extracts namespace from aggregate cursor stage explains" do
    namespace = described_class.namespace_for(
      aggregate_explain_result,
      "treasurer",
      { "aggregate" => "teams" },
      "aggregate"
    )

    expect(namespace).to eq("treasurer.teams")
  end

  describe ".enabled?" do
    let(:monitoring_global) { double("mongo_monitoring_global") }

    around do |example|
      previous = ENV["MONGO_EXPLAIN"]
      example.run
    ensure
      ENV["MONGO_EXPLAIN"] = previous
    end

    before do
      monitoring = Module.new
      monitoring.const_set(:Global, monitoring_global)
      monitoring.const_set(:COMMAND, :command)
      mongo = Module.new
      mongo.const_set(:Monitoring, monitoring)
      stub_const("Mongo", mongo)
    end

    it "returns false when MONGO_EXPLAIN is not enabled" do
      ENV["MONGO_EXPLAIN"] = "0"
      allow(described_class).to receive(:development_mode?).and_return(true)
      allow(described_class).to receive(:explain_client_configured?).and_return(true)

      expect(described_class.enabled?).to eq(false)
    end

    it "returns false when a client provider is unavailable" do
      ENV["MONGO_EXPLAIN"] = "1"
      allow(described_class).to receive(:development_mode?).and_return(true)
      allow(described_class).to receive(:explain_client_configured?).and_return(false)

      expect(described_class.enabled?).to eq(false)
    end

    it "returns true when all monitor prerequisites are met" do
      ENV["MONGO_EXPLAIN"] = "1"
      allow(described_class).to receive(:development_mode?).and_return(true)
      allow(described_class).to receive(:explain_client_configured?).and_return(true)

      expect(described_class.enabled?).to eq(true)
    end
  end

  describe ".install! and .shutdown!" do
    let(:monitoring_global) { double("mongo_monitoring_global") }

    around do |example|
      original_installed = described_class.instance_variable_defined?(:@installed) ? described_class.instance_variable_get(:@installed) : :undefined
      original_queue = described_class.instance_variable_defined?(:@queue) ? described_class.instance_variable_get(:@queue) : :undefined
      original_workers = described_class.instance_variable_defined?(:@workers) ? described_class.instance_variable_get(:@workers) : :undefined
      original_subscriber = described_class.instance_variable_defined?(:@subscriber) ? described_class.instance_variable_get(:@subscriber) : :undefined

      described_class.instance_variable_set(:@installed, false)
      example.run
    ensure
      {
        "@installed" => original_installed,
        "@queue" => original_queue,
        "@workers" => original_workers,
        "@subscriber" => original_subscriber
      }.each do |name, value|
        if value == :undefined
          described_class.remove_instance_variable(name) if described_class.instance_variable_defined?(name)
        else
          described_class.instance_variable_set(name, value)
        end
      end
    end

    before do
      monitoring = Module.new
      monitoring.const_set(:Global, monitoring_global)
      monitoring.const_set(:COMMAND, :command)
      mongo = Module.new
      mongo.const_set(:Monitoring, monitoring)
      stub_const("Mongo", mongo)
    end

    it "subscribes once even when install! is called repeatedly" do
      worker = double("worker")
      allow(worker).to receive(:join)
      allow(described_class).to receive(:enabled?).and_return(true)
      allow(described_class).to receive(:spawn_worker).and_return(worker)
      allow(described_class).to receive(:build_subscriber).and_return(:subscriber)
      allow(monitoring_global).to receive(:subscribe)

      described_class.install!
      described_class.install!

      expect(monitoring_global).to have_received(:subscribe).once
      expect(described_class.instance_variable_get(:@installed)).to eq(true)
    end

    it "pushes stop signal and joins workers during shutdown" do
      queue = double("queue")
      worker = double("worker")
      allow(queue).to receive(:push)
      allow(worker).to receive(:join)

      described_class.instance_variable_set(:@queue, queue)
      described_class.instance_variable_set(:@workers, [worker])
      described_class.instance_variable_set(:@installed, true)

      described_class.shutdown!

      expect(queue).to have_received(:push).with(described_class::STOP_SIGNAL)
      expect(worker).to have_received(:join).with(0.5)
      expect(described_class.instance_variable_get(:@installed)).to eq(false)
    end
  end

  describe ".process_payload" do
    let(:payload) do
      {
        command_name: "find",
        database_name: "treasurer",
        callsite: "app/models/team.rb:12",
        command: { "find" => "teams" }
      }
    end

    let(:logger) { double("logger", info: nil, debug: nil) }
    let(:formatter) { double("formatter", summary: "summary line", details: "details line", explain_error: "error line") }

    before do
      allow(described_class).to receive(:logger).and_return(logger)
      allow(described_class).to receive(:formatter).and_return(formatter)
      allow(described_class).to receive(:explain_target_for).and_return({ "find" => "teams" })
      allow(described_class).to receive(:run_explain).and_return({ "ok" => 1 })
      allow(described_class).to receive(:winning_plan_for).and_return({ "stage" => "IXSCAN" })
      allow(described_class).to receive(:execution_stats_for).and_return(
        {
          "nReturned" => 1,
          "totalDocsExamined" => 4,
          "totalKeysExamined" => 4,
          "executionTimeMillis" => 2
        }
      )
      allow(described_class).to receive(:namespace_for).and_return("treasurer.teams")
      allow(described_class).to receive(:index_names_for).and_return("team_id_1")
      allow(MongoExplain::Ui::Emitter).to receive(:emit_explain_summary)
      stub_const("MongoExplain::Monitor::LOG_ONLY_COLLSCAN", false)
    end

    it "emits only summary log/event for non-collscan known plans" do
      allow(described_class).to receive(:collscan_plan?).and_return(false)
      allow(described_class).to receive(:plan_stage_path).and_return("IXSCAN")

      described_class.process_payload(payload)

      expect(formatter).to have_received(:summary).with(
        hash_including(operation: "find", plan: "IXSCAN", namespace: "treasurer.teams")
      )
      expect(formatter).not_to have_received(:details)
      expect(logger).to have_received(:info).once
      expect(MongoExplain::Ui::Emitter).to have_received(:emit_explain_summary).with(
        hash_including(collscan: false, unknown_plan: false, plan: "IXSCAN")
      )
    end

    it "emits detail logs for collscan plans" do
      allow(described_class).to receive(:collscan_plan?).and_return(true)
      allow(described_class).to receive(:plan_stage_path).and_return("IXSCAN>COLLSCAN")

      described_class.process_payload(payload)

      expect(formatter).to have_received(:details)
      expect(logger).to have_received(:info).twice
      expect(MongoExplain::Ui::Emitter).to have_received(:emit_explain_summary).with(
        hash_including(collscan: true, unknown_plan: false)
      )
    end

    it "emits detail logs for unknown plans" do
      allow(described_class).to receive(:collscan_plan?).and_return(false)
      allow(described_class).to receive(:plan_stage_path).and_return("UNKNOWN")

      described_class.process_payload(payload)

      expect(formatter).to have_received(:details)
      expect(MongoExplain::Ui::Emitter).to have_received(:emit_explain_summary).with(
        hash_including(collscan: false, unknown_plan: true, plan: "UNKNOWN")
      )
    end

    it "skips non-collscan payloads when LOG_ONLY_COLLSCAN is enabled" do
      stub_const("MongoExplain::Monitor::LOG_ONLY_COLLSCAN", true)
      allow(described_class).to receive(:collscan_plan?).and_return(false)

      described_class.process_payload(payload)

      expect(logger).not_to have_received(:info)
      expect(MongoExplain::Ui::Emitter).not_to have_received(:emit_explain_summary)
    end
  end

  describe ".explain_target_for" do
    it "returns nil when the command does not match the operation" do
      command = { "aggregate" => "teams", "$db" => "treasurer" }

      expect(described_class.explain_target_for("find", command)).to be_nil
    end

    it "removes internal command keys and comments from explain targets" do
      command = {
        "find" => "teams",
        "filter" => { "name" => "A" },
        "$db" => "treasurer",
        "lsid" => { "id" => "x" },
        "comment" => "manual-marker"
      }

      explain_target = described_class.explain_target_for("find", command)

      expect(explain_target).to eq(
        {
          "find" => "teams",
          "filter" => { "name" => "A" }
        }
      )
    end
  end

  describe "standalone client-provider behavior" do
    around do |example|
      original_provider = if described_class.instance_variable_defined?(:@client_provider)
        described_class.instance_variable_get(:@client_provider)
      else
        :undefined
      end

      described_class.client_provider = nil
      example.run
    ensure
      if original_provider == :undefined
        described_class.remove_instance_variable(:@client_provider) if described_class.instance_variable_defined?(:@client_provider)
      else
        described_class.client_provider = original_provider
      end
    end

    it "returns nil from run_explain when no client provider is configured" do
      result = described_class.run_explain("treasurer", { "find" => "teams" })

      expect(result).to be_nil
    end

    it "uses configured client provider for explain execution" do
      command_calls = []
      database = double("database")
      allow(database).to receive(:command) do |command|
        command_calls << command
        [{ "ok" => 1 }]
      end

      selected_client = double("selected_client", database: database)
      client = double("client")
      allow(client).to receive(:use).with("treasurer").and_return(selected_client)
      described_class.client_provider = -> { client }

      result = described_class.run_explain("treasurer", { "find" => "teams" })

      expect(result).to eq({ "ok" => 1 })
      expect(command_calls.length).to eq(1)
      expect(command_calls.first["verbosity"]).to eq("executionStats")
      expect(command_calls.first["comment"]).to eq(MongoExplain::Monitor::EXPLAIN_COMMENT)
    end
  end
end
