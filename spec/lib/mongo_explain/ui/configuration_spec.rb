# frozen_string_literal: true

require "spec_helper"

RSpec.describe MongoExplain::Ui::Configuration do
  it "sets expected defaults" do
    config = described_class.new

    expect(config.enabled).to eq(false)
    expect(config.channel_name).to eq("mongo_explain:ui")
    expect(config.max_stack).to eq(5)
    expect(config.default_ttl_ms).to eq(12_000)
    expect(config.level_styles).to eq(
      {
        "info" => "mongo-explain-ui-card--info",
        "collscan" => "mongo-explain-ui-card--collscan",
        "warn" => "mongo-explain-ui-card--warn",
        "error" => "mongo-explain-ui-card--error"
      }
    )
  end
end
