# Embedding

Use the library directly when the host project already knows how to gather coverage.

## Precomputed coverage

```lua
local report = require("crap4lua.report")

local result = assert(report.build({
  project_root = "/path/to/project",
  project_name = "Host App",
  source_roots = { "src", "lib" },
  coverage_result = {
    line_hits = {
      ["src/example.lua"] = {
        [10] = true,
        [11] = true,
      },
    },
    lanes = {
      {
        lane = "unit",
        mode = "ci",
        total = 42,
        failed = false,
        failure_count = 0,
        failures = {},
      },
    },
  },
}))
```

## Adapter-driven coverage

```lua
local report = require("crap4lua.report")

local result = assert(report.build({
  project_root = "/path/to/project",
  project_name = "Host App",
  source_roots = { "src" },
  coverage = {
    lanes = { "unit", "integration" },
    mode = "ci",
    adapter = {
      resolve_suites = function(lane, mode)
        return discover_suites(lane, mode), mode
      end,
      run = function(suites, opts)
        return run_host_tests(suites, opts)
      end,
      debug_api = debug,
    },
  },
}))
```

## Output contract

`report.build()` returns a table containing:

- `metadata.project_name`
- `metadata.project_root`
- `metadata.source_roots`
- `summary.module_count`
- `summary.function_count`
- `summary.total_crap`
- `lanes`
- `modules`
- `functions`

Use `require("crap4lua.viewer").write()` to render the static viewer bundle from that table.
