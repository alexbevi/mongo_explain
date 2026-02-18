# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/mongo_explain/ui/overlay_helper"

RSpec.describe MongoExplain::Ui::OverlayHelper do
  let(:configuration) do
    double(
      "configuration",
      enabled: true,
      channel_name: "mongo_explain:test",
      max_stack: 8,
      default_ttl_ms: 9_000
    )
  end

  let(:helper_class) do
    Class.new do
      include MongoExplain::Ui::OverlayHelper

      attr_writer :signed_in

      def user_signed_in?
        !!@signed_in
      end
    end
  end

  subject(:helper_instance) { helper_class.new }

  before do
    allow(MongoExplain::Ui).to receive(:configuration).and_return(configuration)
  end

  it "returns false when no user is signed in" do
    helper_instance.signed_in = false

    expect(helper_instance.mongo_explain_overlay_enabled?).to eq(false)
  end

  it "returns config enabled state when user is signed in" do
    helper_instance.signed_in = true

    expect(helper_instance.mongo_explain_overlay_enabled?).to eq(true)
  end

  it "exposes channel and display configuration" do
    expect(helper_instance.mongo_explain_overlay_channel_name).to eq("mongo_explain:test")
    expect(helper_instance.mongo_explain_overlay_max_stack).to eq(8)
    expect(helper_instance.mongo_explain_overlay_default_ttl_ms).to eq(9_000)
  end
end
