local function _normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function _repo_root()
  local raw_path = arg and arg[0] or "bin/crap4lua.lua"
  local normalized = _normalize_path(raw_path)
  return normalized:match("^(.*)/bin/[^/]+$") or "."
end

local repo_root = _repo_root()
package.path = repo_root .. "/lib/?.lua;" .. repo_root .. "/lib/?/?.lua;" .. package.path

local crap4lua = require("crap4lua")
crap4lua.run(arg or {}, {
  command_name = "bin/crap4lua.lua",
})
