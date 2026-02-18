# AGENTS.md - mongo_explain Engine Instructions

This repository contains the standalone `mongo_explain` Rails engine/gem extracted from the Hockey Team Budget app.

## Project Overview

- Ruby gem + Rails engine (`mongo_explain`)
- Primary entrypoint: `lib/mongo_explain.rb`
- Main layers:
  - Core monitor: `lib/mongo_explain/development_monitor.rb`
  - UI engine + overlay: `lib/mongo_explain/ui/*`

## Critical Rules

1. Keep the core monitor and UI engine concerns separated.
2. Avoid host-app-specific coupling (no app-specific constants, models, routes, or auth assumptions).
3. Keep environment flags stable and backward-compatible:
   - `MONGO_EXPLAIN`
   - `MONGO_EXPLAIN_ONLY_COLLSCAN`
   - `MONGO_EXPLAIN_UI`
   - `MONGO_EXPLAIN_UI_CHANNEL`
   - `MONGO_EXPLAIN_UI_MAX_STACK`
   - `MONGO_EXPLAIN_UI_TTL_MS`
4. Preserve log contracts consumed by developers:
   - summary lines include callsite, operation, namespace, plan stage path, index names, and execution stats
   - detail JSON lines are emitted for `COLLSCAN` and `UNKNOWN` plans
5. Preserve terminal log color behavior (green when tty supports ANSI; respect `NO_COLOR`).
6. Prefer minimal dependencies; do not add gems unless clearly required.
7. Preserve Rails-engine behavior for importmap/assets/view helper wiring in `lib/mongo_explain/ui/engine.rb`.
8. Keep runtime safe outside Rails boot where practical (guard Rails-specific loads).
9. ActionCable channel implementation must not depend on host `ApplicationCable`; use `ActionCable::Channel::Base`.
10. Update specs when behavior changes in parser/planner/stat extraction, event emission, dedupe, or overlay rendering logic.
11. Keep README/docs aligned with code changes and public configuration.
12. Maintain semantic versioning in `lib/mongo_explain/version.rb` for publishable changes.

## Behavior Contracts

### Monitor behavior
- Supported monitored command names: `find`, `aggregate`, `count`, `distinct`.
- Explain probes run with execution stats verbosity and use an internal comment marker to prevent recursion.
- `MONGO_EXPLAIN_ONLY_COLLSCAN=1` limits monitor logs/events to winning plans containing `COLLSCAN`.
- Callsite detection should prefer app/lib callsites and avoid self-noise from monitor internals.

### UI behavior
- UI is development-only and enabled via `MONGO_EXPLAIN_UI=1`.
- Enabling UI also enables core monitor (`MONGO_EXPLAIN=1`) during engine initialization.
- Overlay uses ActionCable broadcast events with normalized payload fields from `MongoExplain::Ui::Event`.
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
