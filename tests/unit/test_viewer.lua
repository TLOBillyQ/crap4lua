local bootstrap = require("tests.support.bootstrap")
local common = require("crap4lua.common")
local viewer = require("crap4lua.viewer")
local helpers = require("tests.support.helpers")

bootstrap.install_package_paths()

local function _test_viewer_writes_static_bundle_from_packaged_assets()
  helpers.with_temp_fixture({}, function(tmp_root)
    local ok, err = viewer.write({
      out_dir = tmp_root .. "/viewer_out",
    }, {
      metadata = {
        project_name = "Viewer Fixture",
        source_roots = { "lib" },
      },
      summary = { module_count = 1, function_count = 1, total_crap = 12.5, critical_function_count = 0 },
      modules = {
        { source_name = "lib/sample", source_path = "lib/sample.lua", max_function_crap = 12.5, function_count = 1 },
      },
      functions = {
        {
          name = "alpha",
          source_path = "lib/sample.lua",
          start_line = 1,
          end_line = 4,
          crap = 12.5,
          complexity = 3,
          coverage = 0.5,
          executable_line_count = 4,
          hit_line_count = 2,
          risk_band = "warning",
        },
      },
      lanes = {},
    }, {
      open = false,
    })
    if not ok then
      error(err)
    end
    local index_content = assert(common.read_file(tmp_root .. "/viewer_out/index.html"))
    helpers.assert_contains(index_content, "href=\"styles.css\"", "viewer index should include stylesheet asset")
    helpers.assert_contains(index_content, "src=\"crap_report_data.js\"", "viewer index should include report payload")
    local data_js = assert(common.read_file(tmp_root .. "/viewer_out/crap_report_data.js"))
    helpers.assert_contains(data_js, "window.CRAP_REPORT_DATA", "viewer should embed report payload")
  end)
end

local function _test_viewer_open_prints_index_and_uses_open_path()
  helpers.with_temp_fixture({}, function(tmp_root)
    local printed = {}
    local original_print = print
    local original_open_path = common.open_path
    local opened_path = nil
    print = function(...)
      local parts = {}
      for index = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(index, ...))
      end
      printed[#printed + 1] = table.concat(parts, "\t")
    end
    common.open_path = function(path)
      opened_path = path
      return true
    end

    local ok, err = viewer.write({
      out_dir = tmp_root .. "/viewer_open_out",
    }, {
      metadata = {
        project_name = "Viewer Fixture",
        source_roots = { "lib" },
      },
      summary = { module_count = 1, function_count = 1, total_crap = 1.0, critical_function_count = 0 },
      modules = {},
      functions = {},
      lanes = {},
    }, {
      open = true,
    })

    print = original_print
    common.open_path = original_open_path
    if not ok then
      error(err)
    end

    local expected_index = tmp_root .. "/viewer_open_out/index.html"
    helpers.assert_eq(opened_path, expected_index, "viewer should open resolved index path")
    helpers.assert_contains(table.concat(printed, "\n"), "viewer_opened=" .. expected_index, "viewer should print opened index path")
  end)
end

return {
  name = "crap4lua.unit.viewer",
  tests = {
    { name = "viewer_writes_static_bundle_from_packaged_assets", run = _test_viewer_writes_static_bundle_from_packaged_assets },
    { name = "viewer_open_prints_index_and_uses_open_path", run = _test_viewer_open_prints_index_and_uses_open_path },
  },
}
