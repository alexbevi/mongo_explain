# MongoExplain

MongoExplain is development-only tooling for spotting expensive and unindexed MongoDB operations, helping developers apply MongoDB [Query Optimization](https://www.mongodb.com/docs/manual/core/query-optimization/) best practices.

It combines:
- a low-noise explain monitor that writes structured summary/detail logs
- an optional Rails ActionCable overlay for live query-plan feedback in the browser

## Development-Only Usage

MongoExplain should only be used in development environments.

It relies on the [MongoDB Ruby driver's command event monitoring](https://www.mongodb.com/docs/ruby-driver/current/logging-and-monitoring/monitoring/#std-label-ruby-command-monitoring) to capture raw commands, duplicate command shapes, and generate [`explain` plans](https://www.mongodb.com/docs/manual/reference/command/explain/) with [`executionStats` verbosity](https://www.mongodb.com/docs/manual/reference/command/explain/#std-label-ex-executionStats). This adds overhead and is not intended for production traffic.

For deeper protocol details, see MongoDB's [Command Logging and Monitoring](https://alexbevi.com/specifications/command-logging-and-monitoring/command-logging-and-monitoring.html) specification.

## Installation

```ruby
# Gemfile
gem "mongo_explain", git: "https://github.com/alexbevi/mongo_explain.git"
```

## Usage Modes

### Rails Engine Integration (Overlay + Logs)

![Rails engine integration with in-app overlay](docs/ss01.png)

Use this mode when you want explain visibility directly in the app UI while navigating pages.

1. Ensure the gem is available in your Rails app.
2. Enable UI mode:

```bash
export MONGO_EXPLAIN_UI=1
```

3. Render the overlay partial in your layout:

```erb
<%= render "mongo_explain/ui/overlay" %>
```

Notes:
- UI mode is Rails-only.
- When UI is enabled, the engine also enables `MONGO_EXPLAIN=1` in development.
- Explain probes default to `Mongoid.default_client` when Mongoid is present.
- UI cards are merged/stacked for repeated calls (example: `MongoExplain FIND (7)`), which can reveal repeated-query optimization opportunities.
- This can also expose unexpected query activity from navigation behavior (for example, when [Turbo prefetching is enabled](https://turbo.hotwired.dev/handbook/drive#prefetching-links-on-hover)).

### Console-Only / Standalone Library (Logger Output)

![Console-only usage with logger output](docs/ss02.png)

Use this mode when you want query-plan monitoring without Rails or without the UI overlay.

Configure a client provider (required for explain probes in standalone mode):

```ruby
MongoExplain::DevelopmentMonitor.configure do |config|
  config.client_provider = -> { mongo_client } # Mongo::Client-compatible
  # config.logger = Logger.new($stdout)         # optional custom logger
end
```

Enable monitor mode:

```bash
export MONGO_EXPLAIN=1
```

Optional restriction (log only plans containing `COLLSCAN`):

```bash
export MONGO_EXPLAIN_ONLY_COLLSCAN=1
```

## Environment Flags

- `MONGO_EXPLAIN=1`: enable explain monitoring
- `MONGO_EXPLAIN_ONLY_COLLSCAN=1`: log/event only plans containing `COLLSCAN`
- `MONGO_EXPLAIN_UI=1`: enable development overlay (Rails only)
- `MONGO_EXPLAIN_UI_CHANNEL`: override ActionCable channel name (default `mongo_explain:ui`)
- `MONGO_EXPLAIN_UI_MAX_STACK`: max visible overlay cards (default `5`)
- `MONGO_EXPLAIN_UI_TTL_MS`: default card TTL in milliseconds (default `12000`)

## Logging Output

MongoExplain prefers `Rails.logger` when Rails is loaded and falls back to a standard Ruby logger on `$stdout` otherwise.

Summary logs include:
- callsite
- operation
- namespace
- plan stage path
- index names
- `nReturned`, docs examined, keys examined, execution ms

Example summary line:

```text
[MongoExplain] callsite=app/models/concerns/team_financial_calculations.rb:112 op=aggregate ns=treasurer.transactions plan=GROUP>FETCH>IXSCAN index=team_id_1_transaction_date_-1 returned=1 docs=209 keys=209 ms=5
```

### Why callsite matters

`callsite` is one of the highest-value fields. It points to where in the Ruby/Rails codebase the monitored operation originated (for example `app/controllers/...` or `app/services/...`).

Use `callsite` to:
- map a slow or `COLLSCAN` plan to the exact triggering code path
- separate framework/internal queries from application queries
- detect repeated query patterns from specific actions/scopes/services
- prioritize fixes by frequency and impact

Detail logs include JSON payloads for:
- explain target command
- winning plan
- execution stats

Detail logs are emitted when:
- winning plan contains `COLLSCAN`, or
- computed plan path resolves to `UNKNOWN`
