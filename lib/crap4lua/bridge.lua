local common = require("crap4lua.common")
local config = require("crap4lua.config")
local coverage = require("crap4lua.coverage")
local json_writer = require("crap4lua.json_writer")

local bridge = {}

local function _to_array(value)
    if type(value) ~= "table" then
        return {}
    end
    local out = {}
    for _, item in ipairs(value) do
        out[#out + 1] = item
    end
    return out
end

local function _parse_top_level_args(argv)
    local args = argv or {}
    local parsed = {
        command = args[1],
        subcommand = args[2],
        config = nil,
        out = nil,
        mode = nil,
        project_root = nil,
        lanes = {},
    }

    local index = 3
    if parsed.command ~= "bridge" then
        index = 2
    end

    while index <= #args do
        local token = args[index]
        if token == "--config" then
            parsed.config = args[index + 1]
            index = index + 2
        elseif token == "--out" then
            parsed.out = args[index + 1]
            index = index + 2
        elseif token == "--mode" then
            parsed.mode = args[index + 1]
            index = index + 2
        elseif token == "--project-root" then
            parsed.project_root = args[index + 1]
            index = index + 2
        elseif token == "--lane" then
            parsed.lanes[#parsed.lanes + 1] = args[index + 1]
            index = index + 2
        else
            error("Unknown flag: " .. tostring(token))
        end
    end

    return parsed
end

local function _active_lanes(cli_lanes, config_lanes)
    if type(cli_lanes) == "table" and #cli_lanes > 0 then
        return _to_array(cli_lanes)
    end
    if type(config_lanes) == "table" and #config_lanes > 0 then
        return _to_array(config_lanes)
    end
    return { "default" }
end

local function _collect_from_loaded_config(loaded, opts)
    local project_root = loaded.project_root
    if opts.project_root ~= nil and opts.project_root ~= "" then
        project_root = common.resolve_cli_path(common.current_dir(), opts.project_root)
    end

    local coverage_cfg = loaded.coverage or {}
    local lanes = _active_lanes(opts.lanes, coverage_cfg.lanes)
    local mode = opts.mode or coverage_cfg.mode

    local result = coverage.collect({
        project_root = project_root,
        tracked_sources = coverage_cfg.tracked_sources or {},
        source_roots = loaded.source_roots,
        lanes = lanes,
        mode = mode,
        adapter = coverage_cfg.adapter,
    })

    return {
        project_root = project_root,
        project_name = loaded.project_name,
        source_roots = loaded.source_roots,
        coverage_result = result,
    }
end

function bridge.collect(opts, env)
    opts = opts or {}
    env = env or {}

    local loaded, err = (env.load_config or config.load)(opts.config, env)
    if loaded == nil then
        return nil, err
    end

    local ok, response_or_err = xpcall(function()
        return _collect_from_loaded_config(loaded, opts)
    end, debug.traceback)

    if not ok then
        return nil, response_or_err
    end
    return response_or_err
end

function bridge.write_collect_json(opts, env)
    local result, err = bridge.collect(opts, env)
    if result == nil then
        return nil, err
    end

    local encoded = json_writer.encode(result)
    if opts.out ~= nil and opts.out ~= "" then
        local out_path = common.resolve_cli_path(common.current_dir(), opts.out)
        local ok, write_err = common.write_file(out_path, encoded)
        if not ok then
            return nil, write_err
        end
        return result, nil
    end

    io.write(encoded)
    io.write("\n")
    return result, nil
end

function bridge.run_cli(args, env)
    local parsed = _parse_top_level_args(args or {})
    if parsed.command == "collect" then
        -- allow direct shape: collect --config ... --out ...
        local ok, err = bridge.write_collect_json(parsed, env)
        if not ok then
            error(err)
        end
        return true
    end

    if parsed.command == "bridge" and parsed.subcommand == "coverage" then
        local ok, err = bridge.write_collect_json(parsed, env)
        if not ok then
            error(err)
        end
        return true
    end

    error("Unsupported bridge command. Use `collect` or `bridge coverage`.")
end

return bridge
