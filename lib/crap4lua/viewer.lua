local common = require("crap4lua.common")
local engine = require("crap4lua.engine")
local json_reader = require("crap4lua.json_reader")
local json_writer = require("crap4lua.json_writer")
local report_builder = require("crap4lua.report")

local viewer = {}

function viewer.load_report(path)
  local content, err = common.read_file(path)
  if content == nil then
    return nil, err
  end
  return json_reader.decode(content)
end

function viewer.write(paths, data, opts)
  local out_dir = paths.out_dir
  local temp_json = common.make_temp_path("crap4lua_viewer", ".json")
  local ok, err = common.write_file(temp_json, json_writer.encode(data))
  if not ok then
    return nil, err
  end

  local run_ok, run_err = engine.run_viewer(temp_json, out_dir, {
    open = false,
  }, opts and opts.engine_env or paths.engine_env)
  common.remove_path(temp_json)
  if not run_ok then
    return nil, run_err
  end

  if opts and opts.open then
    local index_path = common.join_path(out_dir, "index.html")
    local opened, open_err = common.open_path(index_path)
    if not opened then
      return nil, open_err
    end
    print("[crap] viewer_opened=" .. tostring(index_path))
  end
  return true
end

function viewer.build_default(opts)
  return report_builder.build(opts or {})
end

return viewer
