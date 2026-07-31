# crap4lua

`crap4lua` is a pure-Lua CRAP (Change Risk Anti-Patterns) hotspot analyzer for
Lua code. It computes cyclomatic complexity from a real Lua AST (via luacheck),
reads line coverage from a standard `luacov.report.out` produced by the host's
test run, and generates JSON reports.

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
lua crap.lua summary --in-json FILE [--tier-config FILE] [--gate] [--gate-threshold N]
```

`--gate` exits `2` when any coverage tier fails or the report's max CRAP
exceeds `--gate-threshold` (default **5.0**).

## Upstream Alignment (对齐上游)

`crap4lua` follows the "Lua faithful implementation of the upstream spec"
doctrine: whatever crap4clj / crap4go / crap4java do identically is the spec
and is copied verbatim; anything different is a deliberate deviation, recorded
here with its reason. Cross-repo decisions live as ADRs in the luatools notes
repo (`projects/luatools/docs/adr/`).

**Aligned invariants (对齐不变量)**

- CRAP formula `CC² × (1 − cov)³ + CC`; missing coverage yields an empty
  score shown as `N/A` — never treated as 0 (JSON `null`, sorted last).
- Risk bands `1–5 low / 5–30 moderate / 30+ high`.
- Five-stage skeleton: find sources → parse function boundaries → compute CC
  → attribute coverage to functions → sort and print.
- `collect` deletes stale coverage artifacts before regenerating.
- Coverage comes only from parsing the ecosystem-standard tool's fixed
  artifact — **luacov** is the sole coverage path (ADR-0003; the local
  `debug.sethook` adapter contract is removed).
- Cyclomatic complexity computed from a real Lua AST (ADR-0001: luacheck
  parser via LuaRocks replaces `luac -p -l` bytecode opcode counting).

**Deliberate deviations (有意偏离)**

- JSON report output (all three upstreams print text tables only) — CI and
  visualization consumption.
- Command split `collect / report / summary / dry-run` instead of one
  end-to-end analyze run.
- `summary --gate` quality gate — the correct port of crap4java's exit-2
  gating, but with a **configurable** threshold (default 5.0; java hardcodes
  8.0, recorded upstream as a lesson).

**Breaking changes on this branch**: the risk-band tightening (5 vs 8), the
luacov-only coverage path, and the gate exit-code/threshold semantics all
change host-visible behavior — see "Compatibility notes" for the full list.

## Host Adapter Contract

The host supplies an adapter table (usually via a Lua file referenced from the
config) bridging the analyzer to the host's test runner. The adapter's one
coverage-related obligation: **run the test suite under luacov so that a
standard `luacov.report.out` appears at `opts.report_path`**. crap4lua parses
that artifact itself; there is no in-process coverage machinery anymore (the
old `debug.sethook` contract is removed, ADR-0003). `collect` deletes any
stale report before running tests.

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
  -- Required: run the suites under luacov and leave a luacov.report.out at
  -- opts.report_path. Receives a silent reporter and
  -- raise_on_failure = false.
  run = function(suites, opts)
    -- e.g. any wiring that produces the standard report at opts.report_path,
    -- such as running the suite with `lua -lluacov` and invoking `luacov`.
    return { total = 0, failed = false, failures = {} }
  end,
  -- Optional: used by `dry-run` to list spec/test files for a lane.
  discover_specs = function(lane)
    return { "tests/example_test.lua" }
  end,
}
```

If no report exists after the run, coverage is **unavailable**: every CRAP
score is `null` (never 0), shown as `N/A`, sorted last.

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
    report = "luacov.report.out", -- optional; default under project_root
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
   - `default_gate_threshold` — max-CRAP gate threshold for `summary --gate`
     (default `5.0`).
   - `tmp_root` / `tmp_env_var` — where `tmp/...` CLI paths resolve
     (default: system temp dir).
   - `cwd`, `stdout`, `stderr` — I/O overrides (useful for embedding/tests).

5. Run `lua crap.lua report --out tmp/crap_report.json`.

For programmatic use, `crap4lua.bridge` exposes `bridge.collect(opts, env)` and
`bridge.write_collect_json(opts, env)`, which return `result, err` instead of
writing to streams.

## Compatibility notes

- **Breaking (landing-alignment branch)**: risk bands are now the upstream
  `1–5 low / 5–30 moderate / 30+ high` (was `8+ warning / 30+ critical`); the
  JSON summary fields `critical_count`/`warning_count` are renamed
  `high_count`/`moderate_count` and joined by `na_count`. `--gate` trips exit
  `2` (was `1`) and now also checks max CRAP against `--gate-threshold`
  (default 5.0).
- **Breaking**: the `debug.sethook` adapter coverage contract is removed.
  Adapters must run tests under luacov and produce `luacov.report.out`;
  `debug_api` and the `before_case`/`after_case` coverage hooks are gone.
  Functions without measurable coverage now report `crap: null` (N/A, sorted
  last) instead of being scored at 0% coverage.
- **Breaking**: complexity comes from the luacheck AST, not `luac -p -l`;
  `luac` is no longer needed and the `env.luac_cmd` knob is removed. Install
  luacheck via LuaRocks instead. The per-function `decision_line_count` JSON
  field is gone (AST complexity has no line-attributed decision list).
- The fallback lane name when none is configured or passed via `--lane` is
  `"default"` (previously `"behavior"`, a leftover from the original host).
  This only affects runs that rely on the fallback; explicit `--lane` /
  `coverage.lanes` behavior is unchanged.
- Unknown CLI flags now print an error to stderr and exit 1 instead of
  raising an uncaught Lua error.
- The `viewer` command shown in older revisions of this README is not
  implemented by the in-repo CLI and has been removed from the docs.

## Requirements

- Lua 5.4
- [luacheck](https://github.com/lunarmodules/luacheck) (`luarocks install luacheck`)
- Host tests runnable under [luacov](https://github.com/lunarmodules/luacov)
  (coverage path only; complexity analysis works without it, scores become N/A)

## Tests

```sh
make test            # uses `lua`
make test LUA=lua5.4 # override the interpreter if needed
```

---

## 中文文档

`crap4lua` 是纯 Lua 的 CRAP 热点分析工具。它用 luacheck 的 AST 计算圈复杂度，
从宿主测试运行产出的标准 `luacov.report.out` 解析行覆盖率（ADR-0003：luacov 是唯一
覆盖率路径，旧的 debug.sethook adapter 契约已移除），并生成 JSON 报告。
库本身不含任何宿主专属路径；接入方式见上文 "Integrating into a new project (eggy)"
一节：宿主需提供 config 文件、adapter 和一个薄入口脚本，并以 luarocks 安装 luacheck。

破坏性变更（landing-alignment 分支）：风险带对齐上游 `1–5 low / 5–30 moderate / 30+ high`；
`--gate` 触发时退出码 2，并检查 max CRAP 是否超过 `--gate-threshold`（默认 5.0）；
缺失覆盖率的函数 CRAP 为 `null`（N/A 沉底，绝不当 0）。
