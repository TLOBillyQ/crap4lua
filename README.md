# crap4lua

`crap4lua` is a standalone Lua toolchain for computing CRAP hotspots from `luac`
complexity listings plus injected dynamic coverage data.

The project is now split into two layers:

- `cmd/crap4lua-go/` + `internal/...` - the Go performance engine
- `lib/crap4lua/` - Lua config, coverage, and compatibility wrappers
- `bin/crap4lua.lua` - Lua CLI entrypoint
- `examples/basic/` - runnable example config + adapter
- `docs/` - CLI, embedding, and migration notes

## Host boundary

`crap4lua` does not know how a host project discovers or executes tests.
Hosts integrate through a single adapter object:

```lua
{
  resolve_suites = function(lane, mode) ... end,
  run = function(suites, opts) ... end,
  debug_api = debug, -- optional
}
```

The Lua layer still collects runtime coverage. The Go layer owns source scanning,
`luac` parsing, CRAP calculation, report assembly, and viewer bundle export.

## CLI

Lua compatibility entrypoint:

```sh
lua bin/crap4lua.lua report --config examples/basic/crap4lua.config.lua --out tmp/report.json
lua bin/crap4lua.lua viewer --in-json tmp/report.json --out-dir tmp/crap_view --open
```

Go-native entrypoint:

```sh
make build-go
./bin/crap4lua-go report --request-json /tmp/request.json --response-json /tmp/response.json
./bin/crap4lua-go viewer --in-json /tmp/response.json --out-dir /tmp/crap_view
```

The Lua wrapper resolves the Go engine in this order:

1. `CRAP4LUA_GO_BIN`
2. `bin/crap4lua-go`
3. local `go build -o bin/crap4lua-go ./cmd/crap4lua-go`

If none of those succeed, the wrapper fails with a build hint.

## Config shape

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

## Tests

```sh
make test-go
make test-lua
```

## Packaging

A LuaRocks spec is included as `/Users/billyq/Dev/Github/Lua/crap4lua/crap4lua-dev-1.rockspec`.
