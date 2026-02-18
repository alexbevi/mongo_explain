# frozen_string_literal: true

module MongoExplain
  module Ui
    class Engine < ::Rails::Engine
      isolate_namespace MongoExplain::Ui
      paths["config/routes.rb"] = []

      initializer "mongo_explain.ui.configuration" do
        if Rails.env.development? && ENV["MONGO_EXPLAIN_UI"] == "1"
          ENV["MONGO_EXPLAIN"] = "1"
        end

        MongoExplain::Ui.configure do |config|
          ui_enabled_env = ENV.fetch("MONGO_EXPLAIN_UI", "0")
          config.enabled = Rails.env.development? && ui_enabled_env == "1"
          config.channel_name = ENV.fetch("MONGO_EXPLAIN_UI_CHANNEL", "mongo_explain:ui")
          config.max_stack = ENV.fetch("MONGO_EXPLAIN_UI_MAX_STACK", 5).to_i
          config.default_ttl_ms = ENV.fetch("MONGO_EXPLAIN_UI_TTL_MS", 12_000).to_i
          config.level_styles = {
            "info" => "mongo-explain-ui-card--info",
            "collscan" => "mongo-explain-ui-card--collscan",
            "warn" => "mongo-explain-ui-card--warn",
            "error" => "mongo-explain-ui-card--error"
          }
        end
      end

      initializer "mongo_explain.ui.importmap", before: "importmap" do |app|
        next unless app.config.respond_to?(:importmap)

        app.config.importmap.paths << root.join("lib/mongo_explain/ui/config/importmap.rb")
        app.config.importmap.cache_sweepers << root.join("lib/mongo_explain/ui/app/javascript")
      end

      initializer "mongo_explain.ui.assets" do |app|
        app.config.assets.paths << root.join("lib/mongo_explain/ui/app/assets/stylesheets")
        app.config.assets.paths << root.join("lib/mongo_explain/ui/app/javascript")
      end

      initializer "mongo_explain.ui.channel" do
        require_relative "channel"
      end

      initializer "mongo_explain.ui.helpers" do
        require_relative "overlay_helper"

        ActiveSupport.on_load(:action_controller_base) do
          helper MongoExplain::Ui::OverlayHelper
          prepend_view_path MongoExplain::Ui::Engine.root.join("lib/mongo_explain/ui/app/views")
        end
      end

      initializer "mongo_explain.ui.monitor" do |app|
        app.config.after_initialize do
          next unless defined?(MongoExplain::Monitor)

          MongoExplain::Monitor.install!
        end
      end
    end
  end
end
