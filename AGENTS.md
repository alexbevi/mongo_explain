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
2. Avoid host-app-specific coupling (no app-specific constants, models, or routes).
3. Keep environment flags stable and backward-compatible:
   - `MONGO_EXPLAIN`
   - `MONGO_EXPLAIN_ONLY_COLLSCAN`
   - `MONGO_EXPLAIN_UI`
   - `MONGO_EXPLAIN_UI_CHANNEL`
   - `MONGO_EXPLAIN_UI_MAX_STACK`
   - `MONGO_EXPLAIN_UI_TTL_MS`
4. Prefer minimal dependencies; do not add gems unless clearly required.
5. Preserve Rails-engine behavior for importmap/assets/view helper wiring in `lib/mongo_explain/ui/engine.rb`.
6. Keep runtime safe outside Rails boot where practical (guard Rails-specific loads).
7. Update specs when behavior changes in parser/planner/stat extraction or event emission logic.
8. Keep README/docs aligned with code changes and public configuration.
9. Maintain semantic versioning in `lib/mongo_explain/version.rb` for publishable changes.

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
3. Verify logs/event payload shape remains stable

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
