# CLI

## User-facing commands

```sh
./bin/crap4lua report --config <file> [--lane <name>] [--mode <name>] [--top <n>] [--strict-tests] [--project-root <dir>] [--response-json <file>]
./bin/crap4lua report --request-json <file> --response-json <file>
./bin/crap4lua collect --config <file> --out <json> [--lane <name>] [--mode <name>] [--project-root <dir>]
./bin/crap4lua viewer --in-json <file> --out-dir <dir> [--open]
```

## Responsibilities

### Go CLI
- parse command-line flags
- invoke Lua bridge modules when coverage must be collected
- analyze Lua source with `luac -p -l`
- compute CRAP metrics and write report JSON
- export the viewer bundle

### Lua runtime
- evaluate `crap4lua.config.lua`
- resolve the host adapter
- execute suites through the adapter
- collect line hits with `debug.sethook`
- expose bridge functionality as Lua modules only, not as a separate script entry

## Config contract

`crap4lua.config.lua` must return a table with:
- `project_name` optional display name
- `project_root` optional root directory
- `source_roots` required source directories
- `coverage` optional table with `lanes`, `mode`, and `adapter`

## Output contract

Report JSON emits:
- `metadata.schema_version = 3`
- `metadata.engine = "go"`
