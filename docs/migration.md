# Migration

## What changed

- `crap4lua` now has a Go performance engine under `cmd/crap4lua-go/` and `internal/...`.
- Lua remains the compatibility layer for config loading, host adapters, and coverage collection.
- `report.build()` and `viewer.write()` now call the Go engine instead of running the full analysis in Lua.
- Report JSON now emits `metadata.schema_version = 3` and `metadata.engine = "go"`.
- The wrapper auto-builds `bin/crap4lua-go` when `go` is available.

## New build commands

```sh
make build-go
make test-go
make test-lua
```

## Compatibility

- Existing Lua CLI usage stays valid: `lua bin/crap4lua.lua ...`
- Existing host adapters stay Lua: `resolve_suites`, `run`, `debug_api`
- Existing report/viewer workflows stay recognizable, but the canonical implementation now lives in Go
