# frozen_string_literal: true

require "spec_helper"

RSpec.describe MongoExplain::DevelopmentMonitor do
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

    expect(winning_plan).to be_present
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
        [ { "ok" => 1 } ]
      end

      selected_client = double("selected_client", database: database)
      client = double("client")
      allow(client).to receive(:use).with("treasurer").and_return(selected_client)
      described_class.client_provider = -> { client }

      result = described_class.run_explain("treasurer", { "find" => "teams" })

      expect(result).to eq({ "ok" => 1 })
      expect(command_calls.length).to eq(1)
      expect(command_calls.first["verbosity"]).to eq("executionStats")
      expect(command_calls.first["comment"]).to eq(MongoExplain::DevelopmentMonitor::EXPLAIN_COMMENT)
    end
  end
end
