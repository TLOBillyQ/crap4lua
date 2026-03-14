# crap4lua

`crap4lua` is a standalone Lua toolchain for computing CRAP hotspots from `luac`
complexity listings plus injected dynamic coverage data.

The project is organized as an independent package now:

- `lib/crap4lua/` - reusable library code
- `lib/crap4lua/assets/viewer/` - packaged static viewer assets
- `bin/crap4lua.lua` - CLI entrypoint
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

The core library accepts either:

- a precomputed `coverage_result = { line_hits = ..., lanes = ... }`, or
- a `coverage = { adapter = ..., lanes = ..., mode = ... }` table.

## CLI

Generate a report from a config file:

```sh
lua bin/crap4lua.lua report --config examples/basic/crap4lua.config.lua --out tmp/report.json
```

Render a viewer from a config file:

```sh
lua bin/crap4lua.lua viewer --config examples/basic/crap4lua.config.lua --out-dir tmp/crap_view
```

Render a viewer from an existing JSON report:

```sh
lua bin/crap4lua.lua viewer --in-json tmp/report.json --out-dir tmp/crap_view --open
```

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

Run the standalone suite with:

```sh
lua tests/run.lua
```

## Packaging

A LuaRocks spec is included as `/Users/billyq/Dev/Github/Lua/crap4lua/crap4lua-dev-1.rockspec`.
