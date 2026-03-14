# CLI

## Commands

### `report`

```sh
lua bin/crap4lua.lua report --config <file> [--lane <name>] [--mode <name>] [--out <file>] [--top <n>] [--strict-tests] [--project-root <dir>]
```

- `--config` loads `crap4lua.config.lua`; if omitted, the CLI looks in the current working directory.
- `--lane` can be repeated and overrides `coverage.lanes` from config.
- `--mode` overrides `coverage.mode` from config.
- `--out` writes the JSON report.
- `--strict-tests` exits non-zero when any lane reports failures.

### `viewer`

```sh
lua bin/crap4lua.lua viewer [--config <file>] [--in-json <file>] [--out-dir <dir>] [--open]
```

- `--in-json` renders an existing report without loading project config.
- Without `--in-json`, the command builds a fresh report from config and then writes the viewer bundle.
- `--out-dir` defaults to `tmp/crap_view`.
- `--open` opens `index.html` after writing the bundle.

## Config contract

`crap4lua.config.lua` must return a table with:

- `project_name` - optional display name for the report viewer.
- `project_root` - optional root directory; defaults to the config directory.
- `source_roots` - required list of source roots to scan.
- `coverage` - optional table containing:
  - `lanes` - list of host-defined execution lanes; defaults to `{ "default" }`.
  - `mode` - optional host-defined execution mode.
  - `adapter` - adapter table, function, or relative Lua file path resolving to an adapter table.

## Failure modes

- Missing config yields an actionable CLI error.
- Missing `source_roots` fails before scanning starts.
- Missing adapter methods fail before coverage collection starts.
- `viewer --in-json` never touches host config or adapters.
