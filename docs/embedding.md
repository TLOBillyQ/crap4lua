# Embedding crap4lua

`crap4lua` can be embedded from Lua by requiring its public modules:

- `crap4lua.bridge`
- `crap4lua.config`
- `crap4lua.coverage`
- `crap4lua.analyzer`
- `crap4lua.viewer`

The stable host-facing contract is the coverage adapter table. Hosts are
responsible for resolving suites and running them; `crap4lua` installs coverage
hooks through the adapter's `debug_api`.

```lua
local bridge = require("crap4lua.bridge")

local result = assert(bridge.collect({
  config = "crap4lua.config.lua",
}))
```
