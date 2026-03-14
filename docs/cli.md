# CLI

## User-facing commands

### Go CLI (Recommended)

The Go CLI is the primary entry point for `crap4lua`:

```sh
# Config-driven report generation
./bin/crap4lua-go report --config <file> [--lane <name>] [--mode <name>] [--top <n>] [--strict-tests] [--project-root <dir>] [--response-json <file>]

# Low-level JSON mode (for integration)
./bin/crap4lua-go report --request-json <file> --response-json <file>

# Bridge collection (debug/inspection)
./bin/crap4lua-go collect --config <file> --out <json> [--lane <name>] [--mode <name>]

# Viewer generation
./bin/crap4lua-go viewer --in-json <file> --out-dir <dir> [--open]
```

### Lua wrapper (Compatibility)

The Lua wrapper is maintained for backward compatibility. It forwards to the Go engine:

```sh
lua bin/crap4lua.lua report --config <file> [--lane <name>] [--mode <name>] [--out <file>] [--top <n>] [--strict-tests] [--project-root <dir>]
lua bin/crap4lua.lua viewer [--config <file>] [--in-json <file>] [--out-dir <dir>] [--open]
```

Note: The Lua wrapper will print a deprecation notice in future versions. Migrate to `crap4lua-go`.

The Go CLI is the canonical implementation for:

- CLI parsing and orchestration
- Source scanning
- `luac -p -l` parsing
- CRAP calculation and report JSON generation
- Viewer bundle export

## Architecture

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

## Config contract

`crap4lua.config.lua` must return a table with:

- `project_name` - optional display name for the report viewer
- `project_root` - optional root directory; defaults to the config directory
- `source_roots` - required list of source roots to scan
- `coverage` - optional table containing:
  - `lanes` - list of host-defined execution lanes; defaults to `{ "default" }`
  - `mode` - optional host-defined execution mode
  - `adapter` - adapter table, function, or relative Lua file path resolving to an adapter table

## Output contract

Report JSON keeps the existing top-level shape and now emits:

- `metadata.schema_version = 3`
- `metadata.engine = "go"`
