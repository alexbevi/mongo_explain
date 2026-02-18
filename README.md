# MongoExplain

MongoExplain is a standalone Rails engine with two layers:

- Core (`lib/mongo_explain/development_monitor.rb`)
- UI overlay integration (`lib/mongo_explain/ui/*`)

The top-level entrypoint is `lib/mongo_explain.rb`.

## Architecture

Core responsibilities:

- Subscribe to Mongo command monitoring events
- Run `explain` probes for supported read operations
- Log concise explain summaries
- Log detailed payloads for `COLLSCAN` and `UNKNOWN` plans
- Emit normalized explain events to the UI layer when loaded

UI responsibilities:

- ActionCable stream/channel and broadcaster
- Overlay card rendering and client-side behavior
- Rails engine integration (assets, importmap, helper/view wiring)

## Install (Path Gem)

In a host app `Gemfile`:

```ruby
gem "mongo_explain", path: "../mongo_explain"
```

## Environment Flags

Core:

- `MONGO_EXPLAIN=1` enables explain monitoring
- `MONGO_EXPLAIN_ONLY_COLLSCAN=1` logs only plans with `COLLSCAN`

UI:

- `MONGO_EXPLAIN_UI=1` enables UI overlay in development
- If UI is enabled, engine initialization also sets `MONGO_EXPLAIN=1`
- `MONGO_EXPLAIN_UI_CHANNEL` overrides ActionCable channel name
- `MONGO_EXPLAIN_UI_MAX_STACK` sets max visible cards
- `MONGO_EXPLAIN_UI_TTL_MS` sets default card TTL

## Logging

`MongoExplain::DevelopmentMonitor` prefers `Rails.logger` when Rails is loaded.
If Rails is unavailable, it falls back to a standard Ruby `Logger` (`$stdout`).
