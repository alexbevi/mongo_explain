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
end
