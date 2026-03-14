# Embedding

Use the Lua layer when the host project needs Lua-native config and coverage adapters.
The Lua layer will bridge into the Go engine for static analysis and viewer export.

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
        ["10"] = true,
        ["11"] = true,
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

## Direct Go engine use

If the host already has a JSON coverage payload, it can call the Go engine directly:

```sh
./bin/crap4lua-go report --request-json /tmp/request.json --response-json /tmp/response.json
```

The request JSON carries `project_root`, `project_name`, `source_roots`,
`coverage_result`, `top`, and `strict_tests`.
