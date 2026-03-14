# Migration

## Architecture Change

`crap4lua` has been restructured as a **Go-first** tool:

| Layer | Before | After |
|-------|--------|-------|
| **CLI** | Lua (`bin/crap4lua.lua`) | Go (`crap4lua-go`) |
| **Analyzer** | Lua + Go hybrid | Go (`internal/analyzer`) |
| **Viewer** | Lua wrapper | Go (`internal/viewer`) |
| **Lua role** | Full implementation | Bridge only (`lib/crap4lua/bridge.lua`) |

### What Lua still does (and must do)

- Evaluate `crap4lua.config.lua`
- Load and run host adapters
- Collect line hits via `debug.sethook`

### What Go now does

- CLI parsing and orchestration
- Source scanning
- `luac -p -l` parsing
- CRAP calculation
- Report generation
- Viewer bundle export

## Migration Guide

### CLI Migration

**Before (Lua CLI):**
```sh
lua bin/crap4lua.lua report --config crap4lua.config.lua --out report.json
lua bin/crap4lua.lua viewer --in-json report.json --out-dir viewer --open
```

**After (Go CLI):**
```sh
# Build the Go binary
make build-go

# Config-driven report
./bin/crap4lua-go report --config crap4lua.config.lua --response-json report.json

# Viewer generation
./bin/crap4lua-go viewer --in-json report.json --out-dir viewer

# Or run directly without intermediate JSON
./bin/crap4lua-go report --config crap4lua.config.lua
```

### Programmatic API Migration

**Before (Lua-only):**
```lua
local report = require("crap4lua.report")
local result = report.build({
  project_root = "/path/to/project",
  source_roots = { "src" },
  coverage = { adapter = my_adapter, lanes = { "unit" } },
})
```

**After (Go CLI or bridge):**

Option 1: Use Go CLI directly
```sh
./bin/crap4lua-go report --config crap4lua.config.lua --response-json output.json
```

Option 2: Use collect + report pipeline
```sh
./bin/crap4lua-go collect --config crap4lua.config.lua --out coverage.json
# Then build report with the coverage JSON via analyzer.BuildReport
```

## Compatibility

- **Lua CLI**: Still works, forwards to Go engine. May show deprecation notice in future.
- **Host adapters**: No changes needed. Still Lua: `resolve_suites`, `run`, `debug_api`.
- **Config format**: No changes needed. Still `crap4lua.config.lua`.

## Report JSON Changes

- `metadata.schema_version = 3`
- `metadata.engine = "go"`

## Build Commands

```sh
make build-go    # Build ./bin/crap4lua-go
make test-go     # Run Go tests
make test-lua    # Run Lua tests
make test        # Run all tests
```
