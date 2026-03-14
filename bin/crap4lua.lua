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
local bridge = require("crap4lua.bridge")

local function _is_bridge_command(args)
    local command = args and args[1] or nil
    local subcommand = args and args[2] or nil
    if command == "collect" then
        return true
    end
    if command == "bridge" and subcommand == "coverage" then
        return true
    end
    return false
end

local function _run()
    local argv = arg or {}
    if _is_bridge_command(argv) then
        return bridge.run_cli(argv, {
            command_name = "bin/crap4lua.lua",
        })
    end

    return crap4lua.run(argv, {
        command_name = "bin/crap4lua.lua",
    })
end

_run()
