# crap4lua

`crap4lua` is a CRAP (Change Risk Anti-Patterns) analysis tool for Lua code.
It computes CRAP hotspots from `luac` complexity listings plus dynamic coverage data.

## Architecture

**Go-first architecture**: The core implementation is in Go, with Lua serving as the bridge runtime.

```
┌─────────────────────────────────────────────────────────┐
│  Go CLI (cmd/crap4lua-go)                                │
│  - report --config ...                                   │
│  - collect --config ...                                  │
│  - viewer --in-json ...                                  │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Lua Bridge (lib/crap4lua/bridge.lua)                    │
│  - Execute crap4lua.config.lua                           │
│  - Load host adapter                                     │
│  - Collect coverage via debug.sethook                    │
│  - Return JSON to Go                                     │
└─────────────────────────────────────────────────────────┘
```

**What Go does:**
- CLI parsing and orchestration
- Source scanning
- `luac -p -l` parsing
- CRAP calculation
- Report generation
- Viewer bundle export

**What Lua does (and must do):**
- Evaluate `crap4lua.config.lua`
- Load and run host adapters
- Collect line hits via `debug.sethook`

## Quick Start

```sh
# Build the Go CLI
make build-go

# Run analysis
./bin/crap4lua-go report --config examples/basic/crap4lua.config.lua

# Generate viewer
./bin/crap4lua-go report --config examples/basic/crap4lua.config.lua --response-json report.json
./bin/crap4lua-go viewer --in-json report.json --out-dir viewer --open
```

## CLI Commands

### report
Config-driven report generation (recommended):
```sh
./bin/crap4lua-go report --config <file> [--lane <name>] [--mode <name>] [--top <n>] [--strict-tests] [--project-root <dir>] [--response-json <file>]
```

Low-level JSON mode (for integration):
```sh
./bin/crap4lua-go report --request-json <file> --response-json <file>
```

### collect
Bridge collection for debug/inspection:
```sh
./bin/crap4lua-go collect --config <file> --out <json> [--lane <name>] [--mode <name>]
```

### viewer
Generate viewer bundle:
```sh
./bin/crap4lua-go viewer --in-json <file> --out-dir <dir> [--open]
```

## Host Adapter

`crap4lua` does not know how a host project discovers or executes tests.
Hosts integrate through a Lua adapter:

```lua
{
  resolve_suites = function(lane, mode) ... end,
  run = function(suites, opts) ... end,
  debug_api = debug, -- optional
}
```

See `examples/basic/adapter.lua` for a complete example.

## Config Format

`crap4lua.config.lua` returns a Lua table:

```lua
return {
  project_name = "Example App",
  project_root = ".",
  source_roots = { "src" },
  coverage = {
    lanes = { "unit" },
    mode = "example",
    adapter = "adapter.lua",
  },
}
```

## Lua Compatibility

The Lua CLI (`lua bin/crap4lua.lua`) is maintained for backward compatibility but shows a deprecation notice. It forwards all commands to the Go engine.

**Recommended**: Use `./bin/crap4lua-go` directly.

See [docs/migration.md](docs/migration.md) for migration details.

## Tests

```sh
make test-go
make test-lua
```

## Packaging

A LuaRocks spec is included as `/Users/billyq/Dev/Github/Lua/crap4lua/crap4lua-dev-1.rockspec`.
