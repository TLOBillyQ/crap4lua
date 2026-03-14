local common = require("crap4lua.common")
local json_reader = require("crap4lua.json_reader")
local json_writer = require("crap4lua.json_writer")
local report_builder = require("crap4lua.report")

local viewer = {}

local function _copy_asset(paths, asset_name)
  local source_path = common.join_path(paths.asset_root, asset_name)
  local source_text, err = common.read_file(source_path)
  if source_text == nil then
    return nil, err
  end
  return common.write_file(common.join_path(paths.out_dir, asset_name), source_text)
end

function viewer.load_report(path)
  local content, err = common.read_file(path)
  if content == nil then
    return nil, err
  end
  return json_reader.decode(content)
end

function viewer.write(paths, data, opts)
  local ok, mkdir_err = common.ensure_dir(paths.out_dir)
  if not ok then
    return nil, mkdir_err
  end
  local copy_ok, copy_err = _copy_asset(paths, "index.html")
  if not copy_ok then
    return nil, copy_err
  end
  copy_ok, copy_err = _copy_asset(paths, "script.js")
  if not copy_ok then
    return nil, copy_err
  end
  copy_ok, copy_err = _copy_asset(paths, "styles.css")
  if not copy_ok then
    return nil, copy_err
  end

  local json_path = common.join_path(paths.out_dir, "crap_report.json")
  local write_ok, write_err = common.write_file(json_path, json_writer.encode(data))
  if not write_ok then
    return nil, write_err
  end
  write_ok, write_err = common.write_file(
    common.join_path(paths.out_dir, "crap_report_data.js"),
    "window.CRAP_REPORT_DATA = " .. json_writer.encode(data) .. ";\n"
  )
  if not write_ok then
    return nil, write_err
  end
  local index_path = common.join_path(paths.out_dir, "index.html")
  print("[crap] viewer_index=" .. tostring(index_path))
  if opts and opts.open then
    local opened, open_err = common.open_path(index_path)
    if not opened then
      return nil, open_err
    end
    print("[crap] viewer_opened=" .. tostring(index_path))
  end
  print("[crap] viewer_ok=" .. tostring(paths.out_dir))
  return true
end

function viewer.build_default(opts)
  return report_builder.build(opts or {})
end

return viewer
