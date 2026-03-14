# Embedding

## Recommended entrypoints

| Use case | Recommended approach |
| --- | --- |
| Standard workflow | Run the `crap4lua` CLI |
| Collect coverage from Lua | Use `crap4lua.bridge` |
| Build reports inside Go | Call internal Go packages with the current repo layout |

## CLI usage

```sh
./bin/crap4lua report --config /path/to/crap4lua.config.lua --response-json output.json
```

## Lua bridge usage

```lua
local bridge = require("crap4lua.bridge")

local result, err = bridge.collect({
  config = "/path/to/crap4lua.config.lua",
  lanes = { "unit" },
  mode = "ci",
})

assert(result, err)
```

The bridge result contains:
- `project_root`
- `project_name`
- `source_roots`
- `coverage_result.line_hits`
- `coverage_result.lanes`

## Go embedding

The repository exposes analysis code under `internal/` packages. Those packages are useful for in-repo tooling and controlled embedding, but their import paths are not treated as a stable external API.

Typical flow:
1. collect coverage with the Lua bridge or provide `ipc.CoverageResult` yourself
2. build an `ipc.ReportRequest`
3. call the analyzer and consume `ipc.ReportResponse`
