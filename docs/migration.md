# Migration

## What changed

- Library code moved from the repository root into `lib/crap4lua/`.
- Viewer assets moved into `lib/crap4lua/assets/viewer/` and are resolved automatically by the viewer module.
- `report.build()` now requires explicit `source_roots`.
- Dynamic coverage injection now uses `coverage.adapter` instead of separate `resolve_lane_suites` and `run_all` callbacks.
- The CLI no longer assumes a default lane, default source root, or auto-open behavior when invoked without arguments.
- `report` and config-driven `viewer` runs now require `crap4lua.config.lua` unless `viewer --in-json` is used.

## Old to new API mapping

### Source scanning

- Old: implicit `src`
- New: `source_roots = { "src" }`

### Coverage injection

- Old:

```lua
report.build({
  resolve_lane_suites = ...,
  run_all = ...,
  debug_api = debug,
})
```

- New:

```lua
report.build({
  source_roots = { "src" },
  coverage = {
    adapter = {
      resolve_suites = ...,
      run = ...,
      debug_api = debug,
    },
  },
})
```

### CLI

- Old: `lua bin/crap4lua.lua`
- New: `lua bin/crap4lua.lua --help`
- Old: implicit report/viewer generation from repo defaults
- New: explicit `--config` or a colocated `crap4lua.config.lua`
