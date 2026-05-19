# crap4lua

`crap4lua` is a pure-Lua CRAP (Change Risk Anti-Patterns) hotspot analyzer for
Lua code. It collects coverage through host-provided adapters, analyzes function
complexity from `luac -p -l` output, and generates JSON or static HTML reports.

## CLI

```sh
lua tools/quality/crap.lua report [--lane NAME] [--runner NAME] [--out FILE] [--top N]
lua tools/quality/crap.lua collect [--lane NAME] [--runner NAME] --out FILE
lua tools/quality/crap.lua dry-run [--lane NAME] [--runner NAME]
lua tools/quality/crap.lua viewer --in-json FILE --out-dir DIR [--open]
lua tools/quality/crap.lua summary --in-json FILE [--tier-config FILE] [--gate]
```

The library modules live under `lib/crap4lua/` and are self-contained. Hosts wire
their own adapter through a config file.

## Host Adapter Contract

```lua
return {
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
  run = function(suites, opts)
    return { total = 0, failed = false, failures = {} }
  end,
  debug_api = debug,
}
```

## Config Format

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

## Requirements

- Lua
- `luac` available on `PATH`

## Tests

```sh
make test
```

---

## 中文文档

`crap4lua` 是纯 Lua 的 CRAP 热点分析工具。它通过宿主 adapter 收集覆盖率，使用
`luac -p -l` 解析函数复杂度，并生成 JSON / HTML 报告。
