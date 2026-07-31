local bootstrap = require("tests.support.bootstrap")

local common = require("crap4lua._internal.common")

local helpers = {}

function helpers.fixture_path(name)
  return common.resolve_path(bootstrap.project_root, "tests/fixtures/" .. tostring(name or ""))
end

function helpers.with_temp_fixture(files, fn)
  local tmp_root = common.make_temp_path("crap4lua_test")
  local ok, err = common.ensure_dir(tmp_root)
  if not ok then
    error(err)
  end

  for relpath, text in pairs(files or {}) do
    local file_path = common.join_path(tmp_root, relpath)
    ok, err = common.write_file(file_path, text)
    if not ok then
      common.remove_path(tmp_root)
      error(err)
    end
  end

  local passed, result = xpcall(function()
    return fn(tmp_root)
  end, debug.traceback)
  common.remove_path(tmp_root)
  if not passed then
    error(result)
  end
  return result
end

return helpers
