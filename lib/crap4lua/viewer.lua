local common = require("crap4lua._internal.common")
local json_writer = require("crap4lua._internal.json_writer")

local viewer = {}

local function _asset_root()
  local source = debug.getinfo(1, "S").source or "@vendor/crap4lua/lib/crap4lua/viewer.lua"
  local normalized = common.normalize_path(source):gsub("^@", "")
  local root = normalized:match("^(.*)/[^/]+$") or "."
  return common.join_path(root, "assets/viewer")
end

function viewer.generate(report_data, out_dir, opts)
  opts = opts or {}
  local asset_root = opts.asset_root or _asset_root()

  local ok, err = common.copy_tree(asset_root, out_dir)
  if not ok then
    return nil, err
  end

  local data_script = "window.CRAP_REPORT_DATA = " .. json_writer.encode(report_data) .. ";\n"
  ok, err = common.write_file(common.join_path(out_dir, "crap_report_data.js"), data_script)
  if not ok then
    return nil, err
  end

  if opts.open then
    local index_path = common.join_path(out_dir, "index.html")
    local open_ok, open_err = (opts.open_path or common.open_path)(index_path)
    if not open_ok then
      return nil, open_err
    end
  end

  return true
end

return viewer
