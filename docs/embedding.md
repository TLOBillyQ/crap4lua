# Embedding

## Architecture Overview

`crap4lua` is now a Go-first tool. The embedding patterns have changed:

| Use Case | Recommended Approach |
|----------|---------------------|
| Standard workflow | Use `crap4lua-go` CLI |
| Programmatic Go | Import `internal/analyzer` |
| Custom coverage source | Build `ReportRequest` JSON, call analyzer |
| Lua-only environment | Use Lua bridge (limited) |

## Using the Go CLI

The simplest embedding is calling the Go CLI:

```sh
./bin/crap4lua-go report --config /path/to/crap4lua.config.lua --response-json output.json
```

## Programmatic Go Usage

Import the analyzer package directly:

```go
import "github.com/billyq/crap4lua/internal/analyzer"
import "github.com/billyq/crap4lua/internal/ipc"

req := ipc.ReportRequest{
    ProjectRoot: "/path/to/project",
    ProjectName: "Host App",
    SourceRoots: []string{"src"},
    CoverageResult: ipc.CoverageResult{
        LineHits: map[string]map[string]bool{
            "src/example.lua": {
                "10": true,
                "11": true,
            },
        },
        Lanes: []ipc.LaneResult{
            {Lane: "unit", Total: 42, Failed: false},
        },
    },
    Top: 20,
    StrictTests: false,
}

resp, err := analyzer.BuildReport(req)
```

## Using the Lua Bridge

If you need to collect coverage from Lua runtime:

```lua
local bridge = require("crap4lua.bridge")

-- Collect coverage via bridge
local result, err = bridge.collect({
    config = "/path/to/crap4lua.config.lua",
    lanes = {"unit"},
    mode = "ci",
})

-- result contains:
--   project_root
--   project_name
--   source_roots
--   coverage_result (line_hits, lanes)
```

Then pass the result to Go for analysis:

```sh
./bin/crap4lua-go report --request-json coverage.json --response-json report.json
```

## Host Adapter Contract

Host adapters remain Lua-based. The contract is unchanged:

```lua
{
    resolve_suites = function(lane, mode)
        -- Return: suites, resolved_mode
        return {{name = "test1", path = "tests/test1.lua"}}, mode
    end,
    run = function(suites, opts)
        -- opts: mode, capture_logs, reporter, before_case, after_case
        -- Return: {total = n, failed = bool, failures = {...}}
        return {total = #suites, failed = false, failures = {}}
    end,
    debug_api = debug,  -- optional, defaults to debug
}
```

## Report Request JSON Schema

For direct Go engine use, the request JSON format:

```json
{
    "project_root": "/path/to/project",
    "project_name": "Host App",
    "source_roots": ["src"],
    "coverage_result": {
        "line_hits": {
            "src/example.lua": {
                "10": true,
                "11": true
            }
        },
        "lanes": [
            {
                "lane": "unit",
                "mode": "ci",
                "total": 42,
                "failed": false,
                "failure_count": 0,
                "failures": []
            }
        ]
    },
    "top": 20,
    "strict_tests": false
}
```

Then call:

```sh
./bin/crap4lua-go report --request-json request.json --response-json response.json
```
