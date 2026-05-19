# crap4lua CLI

`crap4lua` exposes a Lua CLI through host wrappers such as
`tools/quality/crap.lua`.

## Commands

```sh
lua tools/quality/crap.lua report [--lane NAME] [--runner NAME] [--out FILE] [--top N]
lua tools/quality/crap.lua collect [--lane NAME] [--runner NAME] --out FILE
lua tools/quality/crap.lua dry-run [--lane NAME] [--runner NAME]
lua tools/quality/crap.lua viewer --in-json FILE --out-dir DIR [--open]
lua tools/quality/crap.lua summary --in-json FILE [--tier-config FILE] [--lane NAME] [--out FILE] [--top N] [--gate]
```

`report` collects coverage, analyzes configured source roots, and writes a report
JSON. `viewer` turns a report JSON into a static HTML bundle. `summary` aggregates
line coverage by tier for gating.

## Report Metadata

Reports include:

- `metadata.engine = "lua"`
- `functions[]` with `crap_score`, `complexity`, `hit_line_count`, and `executable_line_count`
- `modules[]` with per-file aggregate coverage and max CRAP score
- `summary` totals
