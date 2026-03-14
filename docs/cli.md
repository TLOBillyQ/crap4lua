# CLI

## User-facing commands

### Lua wrapper

```sh
lua bin/crap4lua.lua report --config <file> [--lane <name>] [--mode <name>] [--out <file>] [--top <n>] [--strict-tests] [--project-root <dir>]
lua bin/crap4lua.lua viewer [--config <file>] [--in-json <file>] [--out-dir <dir>] [--open]
```

The Lua wrapper loads config, runs host coverage adapters when needed, then delegates
static analysis and viewer export to the Go engine.

### Go engine

```sh
./bin/crap4lua-go report --request-json <file> --response-json <file>
./bin/crap4lua-go viewer --in-json <file> --out-dir <dir> [--open]
```

The Go engine is the canonical implementation for:

- source scanning
- `luac -p -l` parsing
- CRAP calculation and report JSON generation
- viewer bundle export

## Engine resolution

The Lua wrapper resolves the Go binary in this order:

1. `CRAP4LUA_GO_BIN`
2. `bin/crap4lua-go`
3. `go build -o bin/crap4lua-go ./cmd/crap4lua-go`

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
