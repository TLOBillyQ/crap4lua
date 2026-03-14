# crap4lua

`crap4lua` is a standalone Lua toolchain for computing CRAP hotspots from
`luac` complexity listings plus injected dynamic coverage data.

It ships the reusable core pieces:

- `crap4lua.cli`
- `crap4lua.report`
- `crap4lua.coverage`
- `crap4lua.viewer`
- `crap4lua.common`

## Adapter boundary

`crap4lua` does not know how a host project runs its test lanes.
Projects are expected to inject three dependencies when they want dynamic
coverage collection:

- `resolve_lane_suites(lane, mode)`
- `run_all(suites, opts)`
- `debug_api` (optional; defaults to global `debug`)

That keeps the core independent from any specific test catalog or runtime.

## CLI

Run from this repo:

    lua bin/crap4lua.lua --help

The standalone CLI can always render a viewer from an existing JSON report.
Building a fresh report requires an injected coverage adapter.

## Tests

Run the independent contract suite with:

    lua tests/run.lua
