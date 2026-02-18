# frozen_string_literal: true

module MongoExplain
  module Ui
    module Emitter
      module_function

      def emit(title:, message:, level: "info", ttl_ms: nil, dismissible: true, dedupe_key: nil, meta: {})
        event = Event.build(
          title: title,
          message: message,
          level: level,
          ttl_ms: ttl_ms || MongoExplain::Ui.configuration.default_ttl_ms,
          dismissible: dismissible,
          dedupe_key: dedupe_key,
          meta: meta
        )
        Broadcaster.broadcast(event)
      end

      def emit_explain_summary(callsite:, operation:, namespace:, plan:, index:, docs_examined:, keys_examined:, execution_ms:, collscan:, unknown_plan:)
        level = if collscan
          "collscan"
        elsif unknown_plan
          "warn"
        else
          "info"
        end
        title = "MongoExplain #{operation.to_s.upcase}"
        message = "#{namespace} | plan #{plan} | docs #{docs_examined} | keys #{keys_examined} | ms #{execution_ms}"

        emit(
          title: title,
          message: message,
          level: level,
          ttl_ms: ((level == "warn" || level == "collscan") ? 20_000 : 10_000),
          dedupe_key: [ callsite, operation, namespace, plan ].join(":"),
          meta: {
            callsite: callsite,
            operation: operation,
            namespace: namespace,
            plan: plan,
            index: index
          }
        )
      end
    end
  end
end
