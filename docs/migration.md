# Migration Notes

`crap4lua` is now a pure-Lua library and CLI implementation.

Use the host wrapper, usually `tools/quality/crap.lua`, instead of invoking a
vendored executable. Existing config files and coverage adapters continue to use
the same Lua table contracts.

Expected changes for hosts:

- install `lib/?.lua` on `package.path`
- provide a config file with `source_roots` and `coverage.adapter`
- keep `luac` available for report generation
- call `viewer` with an existing report JSON when only the HTML bundle is needed
