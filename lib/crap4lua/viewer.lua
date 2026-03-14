local common = require("crap4lua.common")
local json_reader = require("crap4lua.json_reader")
local json_writer = require("crap4lua.json_writer")
local report_builder = require("crap4lua.report")

local viewer = {}

local function _default_asset_root()
  local source = debug.getinfo(1, "S").source or ""
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  local module_dir = common.parent_dir(common.normalize_path(source)) or "."
  return common.join_path(module_dir, "assets/viewer")
end

local function _copy_asset(asset_root, out_dir, asset_name)
  local source_path = common.join_path(asset_root, asset_name)
  local source_text, err = common.read_file(source_path)
  if source_text == nil then
    return nil, err
  end
  return common.write_file(common.join_path(out_dir, asset_name), source_text)
end

function viewer.load_report(path)
  local content, err = common.read_file(path)
  if content == nil then
    return nil, err
  end
  return json_reader.decode(content)
end

function viewer.write(paths, data, opts)
  local out_dir = paths.out_dir
  local asset_root = paths.asset_root or _default_asset_root()

  local ok, mkdir_err = common.ensure_dir(out_dir)
  if not ok then
    return nil, mkdir_err
  end
  local copy_ok, copy_err = _copy_asset(asset_root, out_dir, "index.html")
  if not copy_ok then
    return nil, copy_err
  end
  copy_ok, copy_err = _copy_asset(asset_root, out_dir, "script.js")
  if not copy_ok then
    return nil, copy_err
  end
  copy_ok, copy_err = _copy_asset(asset_root, out_dir, "styles.css")
  if not copy_ok then
    return nil, copy_err
  end

  local json_path = common.join_path(out_dir, "crap_report.json")
  local write_ok, write_err = common.write_file(json_path, json_writer.encode(data))
  if not write_ok then
    return nil, write_err
  end
  write_ok, write_err = common.write_file(
    common.join_path(out_dir, "crap_report_data.js"),
    "window.CRAP_REPORT_DATA = " .. json_writer.encode(data) .. ";\n"
  )
  if not write_ok then
    return nil, write_err
  end
  local index_path = common.join_path(out_dir, "index.html")
  print("[crap] viewer_index=" .. tostring(index_path))
  if opts and opts.open then
    local opened, open_err = common.open_path(index_path)
    if not opened then
      return nil, open_err
    end
    print("[crap] viewer_opened=" .. tostring(index_path))
  end
  print("[crap] viewer_ok=" .. tostring(out_dir))
  return true
end

function viewer.build_default(opts)
  return report_builder.build(opts or {})
end

return viewer
