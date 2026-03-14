# Migration

## Breaking changes

`crap4lua` is now a single-product CLI with a minimal Lua bridge runtime.

### Removed surfaces
- the legacy Lua command wrapper
- the previous Go-suffixed binary name
- Lua product APIs for report generation, viewer generation, and CLI dispatch

### Retained surfaces
- CLI commands: `crap4lua report`, `crap4lua collect`, `crap4lua viewer`
- Lua runtime APIs: `crap4lua.bridge`, `crap4lua.config`, `crap4lua.coverage`
- host adapter contract: `resolve_suites`, `run`, `debug_api`

## Updated workflow

```sh
make build
./bin/crap4lua report --config crap4lua.config.lua --response-json report.json
./bin/crap4lua viewer --in-json report.json --out-dir viewer
./bin/crap4lua collect --config crap4lua.config.lua --out coverage.json
```

## Packaging changes

- the Go CLI is the official product entrypoint
- the LuaRocks package now contains only the Lua bridge runtime and its private helpers
- Go internal packages remain available for embedding, but they are not part of a stable public API contract
