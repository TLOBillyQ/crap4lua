# crap4lua

`crap4lua` is a pure-Lua CRAP (Change Risk Anti-Patterns) hotspot analyzer for
Lua code. It collects coverage through host-provided adapters, analyzes function
complexity from `luac -p -l` output, and generates JSON reports.

The library modules live under `lib/crap4lua/` and are self-contained: they have
no host-specific paths or defaults baked in. Hosts wire their own adapter and
defaults through a config file and a thin entry script.

## CLI

The library ships no executable of its own; the host provides a small entry
script (see "Integrating into a new project" below). Assuming such a script is
available as `crap.lua`:

```sh
lua crap.lua report [--lane NAME] [--out FILE] [--top N]
lua crap.lua collect [--lane NAME] --out FILE
lua crap.lua dry-run [--lane NAME]
lua crap.lua summary --in-json FILE [--tier-config FILE] [--gate]
```

## Host Adapter Contract

The host supplies an adapter table (usually via a Lua file referenced from the
config) bridging the analyzer to the host's test runner:

```lua
return {
  -- Required: resolve the test suites for a lane. Returns suites, mode.
  resolve_suites = function(lane, mode)
    return {
      {
        name = lane,
        tests = {
          { name = "example", run = function() end },
        },
      },
    }, mode
  end,
  -- Required: run the suites. Receives opts with before_case/after_case
  -- hooks (used to toggle coverage collection), a silent reporter, and
  -- raise_on_failure = false.
  run = function(suites, opts)
    return { total = 0, failed = false, failures = {} }
  end,
  -- Optional: debug library to hook into (defaults to the global `debug`).
  debug_api = debug,
  -- Optional: used by `dry-run` to list spec/test files for a lane.
  discover_specs = function(lane)
    return { "tests/example_test.lua" }
  end,
}
```

## Config Format

The host places a `crap4lua.config.lua` (any path works; pass `--config`):

```lua
return {
  project_name = "Example App",
  project_root = ".",
  source_roots = { "src" },
  coverage = {
    lanes = { "unit" },
    mode = "example",
    adapter = "adapter.lua", -- path relative to the config file,
                             -- or an inline table/function
  },
}
```

## Integrating into a new project (eggy)

A new host project (codename "eggy") integrates with zero changes to this
repository:

1. Vendor the library, e.g. as a git submodule or pinned toolcache checkout at
   `vendor/crap4lua/`.
2. Add `crap4lua.config.lua` at the eggy repo root (see "Config Format"), with
   `source_roots` pointing at eggy's Lua sources.
3. Write `adapter.lua` next to the config, implementing the adapter contract
   above on top of eggy's test runner.
4. Add a thin entry script `crap.lua` at the eggy repo root:

   ```lua
   package.path = "vendor/crap4lua/lib/?.lua;" .. package.path
   os.exit(require("crap4lua.cli").run(arg, {
     command_name = "crap.lua",
     default_config = "crap4lua.config.lua",
   }))
   ```

   `cli.run(args, env)` returns a process exit code. The `env` table lets the
   host inject every default; supported keys:

   - `command_name` — name shown in usage/help text.
   - `default_config` — config path used when `--config` is omitted.
   - `default_report_out` — report path used when `--out` is omitted
     (default `"tmp/crap_report.json"`; `tmp/...` resolves under the tmp root).
   - `default_tier_config` — tier config for `summary` when `--tier-config`
     is omitted.
   - `default_top` — default for `--top`.
   - `luac_cmd` — luac binary to use (default `"luac"`).
   - `tmp_root` / `tmp_env_var` — where `tmp/...` CLI paths resolve
     (default: system temp dir).
   - `cwd`, `stdout`, `stderr` — I/O overrides (useful for embedding/tests).

5. Run `lua crap.lua report --out tmp/crap_report.json`.

For programmatic use, `crap4lua.bridge` exposes `bridge.collect(opts, env)` and
`bridge.write_collect_json(opts, env)`, which return `result, err` instead of
writing to streams.

## Compatibility notes

- The fallback lane name when none is configured or passed via `--lane` is
  `"default"` (previously `"behavior"`, a leftover from the original host).
  This only affects runs that rely on the fallback; explicit `--lane` /
  `coverage.lanes` behavior is unchanged.
- Unknown CLI flags now print an error to stderr and exit 1 instead of
  raising an uncaught Lua error.
- The `viewer` command shown in older revisions of this README is not
  implemented by the in-repo CLI and has been removed from the docs.

## Requirements

- Lua
- `luac` available on `PATH`

## Tests

```sh
make test            # uses `lua`
make test LUA=lua5.4 # override the interpreter if needed
```

---

## 中文文档

`crap4lua` 是纯 Lua 的 CRAP 热点分析工具。它通过宿主 adapter 收集覆盖率，使用
`luac -p -l` 解析函数复杂度，并生成 JSON 报告。库本身不含任何宿主专属路径；
接入方式见上文 "Integrating into a new project (eggy)" 一节：宿主需提供
config 文件、adapter 和一个薄入口脚本。
