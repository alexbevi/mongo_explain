# AGENTS.md - mongo_explain Engine Instructions

This repository contains the standalone `mongo_explain` Rails engine/gem extracted from the Hockey Team Budget app.

## Project Overview

- Ruby gem with optional Rails engine integration (`mongo_explain`)
- Primary entrypoint: `lib/mongo_explain.rb`
- Main layers:
  - Core monitor: `lib/mongo_explain/development_monitor.rb`
  - UI engine + overlay: `lib/mongo_explain/ui/*`

## Critical Rules

1. MongoExplain is development-only tooling and should not be enabled in production.
2. Keep the core monitor and UI engine concerns separated.
3. Avoid host-app-specific coupling (no app-specific constants, models, routes, or auth assumptions).
4. Keep environment flags stable and backward-compatible:
   - `MONGO_EXPLAIN`
   - `MONGO_EXPLAIN_ONLY_COLLSCAN`
   - `MONGO_EXPLAIN_UI`
   - `MONGO_EXPLAIN_UI_CHANNEL`
   - `MONGO_EXPLAIN_UI_MAX_STACK`
   - `MONGO_EXPLAIN_UI_TTL_MS`
5. Preserve log contracts consumed by developers:
   - summary lines include callsite, operation, namespace, plan stage path, index names, and execution stats
   - detail JSON lines are emitted for `COLLSCAN` and `UNKNOWN` plans
6. Preserve terminal log color behavior (green when tty supports ANSI; respect `NO_COLOR`).
7. Prefer minimal dependencies; do not add gems unless clearly required.
8. Preserve Rails-engine behavior for importmap/assets/view helper wiring in `lib/mongo_explain/ui/engine.rb`.
9. Keep runtime safe outside Rails boot (guard Rails-specific loads; standalone mode must still work).
10. ActionCable channel implementation must not depend on host `ApplicationCable`; use `ActionCable::Channel::Base`.
11. Update specs when behavior changes in parser/planner/stat extraction, event emission, dedupe, or overlay rendering logic.
12. Keep README/docs aligned with code changes and public configuration.
13. Maintain semantic versioning in `lib/mongo_explain/version.rb` for publishable changes.

## Behavior Contracts

### Monitor behavior
- Supported monitored command names: `find`, `aggregate`, `count`, `distinct`.
- Monitoring is built on [MongoDB Ruby command event monitoring](https://www.mongodb.com/docs/ruby-driver/current/logging-and-monitoring/monitoring/#std-label-ruby-command-monitoring).
- The monitor captures raw command events, duplicates command shapes, and generates [`explain` plans](https://www.mongodb.com/docs/manual/reference/command/explain/) with [`executionStats` verbosity](https://www.mongodb.com/docs/manual/reference/command/explain/#std-label-ex-executionStats).
- Explain probes use an internal comment marker to prevent recursion.
- `MONGO_EXPLAIN_ONLY_COLLSCAN=1` limits monitor logs/events to winning plans containing `COLLSCAN`.
- Callsite detection should prefer app/lib callsites and avoid self-noise from monitor internals.
- In standalone mode, explain probes require a configured `client_provider`; with Mongoid present, the default provider uses `Mongoid.default_client`.

### UI behavior
- UI is development-only and enabled via `MONGO_EXPLAIN_UI=1`.
- Enabling UI also enables core monitor (`MONGO_EXPLAIN=1`) during engine initialization.
- Overlay uses ActionCable broadcast events with normalized payload fields from `MongoExplain::Ui::Event`.
- Repeated calls are merged/stacked in card titles (example: `MongoExplain FIND (7)`), signaling possible repeated-query optimization opportunities.
- Keep overlay JS/CSS self-contained within engine asset/importmap wiring (no host app JS controller dependency).

## Structure

```
.
├── lib/
│   ├── mongo_explain.rb
│   └── mongo_explain/
│       ├── development_monitor.rb
│       ├── version.rb
│       └── ui/
├── spec/
├── mongo_explain.gemspec
└── README.md
```

## Common Tasks

### Update explain parsing logic
1. Edit `lib/mongo_explain/development_monitor.rb`
2. Add/update specs in `spec/lib/mongo_explain/`
3. Verify summary/detail log shape remains stable

### Update overlay behavior
1. Edit JS/CSS/view files under `lib/mongo_explain/ui/app/`
2. Keep engine importmap/assets wiring intact
3. Validate behavior in both light and dark themes in a host app

### Add configuration
1. Add defaults in `lib/mongo_explain/ui/configuration.rb` and/or engine initializer
2. Document env vars in `README.md`
3. Add specs for new configuration behavior where applicable

## Useful Commands

```bash
bundle install
bundle exec rspec
bundle exec rspec spec/lib/mongo_explain/development_monitor_spec.rb
```
