# crap4lua

`crap4lua` is a CRAP (Change Risk Anti-Patterns) hotspot analyzer for Lua code.
It uses a Go CLI for product workflows and Lua bridge modules for config loading, host adapter execution, and coverage capture.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Go CLI (cmd/crap4lua)                                 │
│  - report --config ...                                 │
│  - collect --config ...                                │
│  - viewer --in-json ...                                │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Lua Bridge Modules                                     │
│  - Execute crap4lua.config.lua                          │
│  - Load host adapter                                    │
│  - Collect coverage via debug.sethook                   │
│  - Return JSON to Go                                    │
└─────────────────────────────────────────────────────────┘
```

## Quick Start

```sh
make build
./bin/crap4lua report --config examples/basic/crap4lua.config.lua
./bin/crap4lua report --config examples/basic/crap4lua.config.lua --response-json report.json
./bin/crap4lua viewer --in-json report.json --out-dir viewer --open
```

## CLI Commands

### report
Config-driven report generation:
```sh
./bin/crap4lua report --config <file> [--lane <name>] [--mode <name>] [--top <n>] [--strict-tests] [--project-root <dir>] [--response-json <file>]
```

Low-level JSON mode:
```sh
./bin/crap4lua report --request-json <file> --response-json <file>
```

### collect
Bridge collection for debugging or inspection:
```sh
./bin/crap4lua collect --config <file> --out <json> [--lane <name>] [--mode <name>] [--project-root <dir>]
```

### viewer
Generate a standalone viewer bundle:
```sh
./bin/crap4lua viewer --in-json <file> --out-dir <dir> [--open]
```

## Public Surfaces

### Official product surface
- CLI: `crap4lua report`, `crap4lua collect`, `crap4lua viewer`
- Lua bridge API: `require("crap4lua.bridge")`
- Lua runtime helpers: `require("crap4lua.config")`, `require("crap4lua.coverage")`

### Host adapter contract
`crap4lua` does not discover or run host tests by itself. Hosts provide a Lua adapter:

```lua
return {
  resolve_suites = function(lane, mode)
    return {
      {
        name = lane,
        tests = {
          { name = "example", run = function() end },
        },
      },
    }, mode
  end,
  run = function(suites, opts)
    return { total = 0, failed = false, failures = {} }
  end,
  debug_api = debug,
}
```

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

## Packaging

The repository includes a LuaRocks spec for the Lua bridge runtime. It installs the bridge/config/coverage modules plus their private runtime helpers; the full product workflow stays in the Go CLI and no standalone Lua entry script is shipped.

## Tests

```sh
make test-go
make test-lua
```
