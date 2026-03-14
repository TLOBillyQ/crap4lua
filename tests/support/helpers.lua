require("tests.support.bootstrap")

local common = require("crap4lua.common")

local helpers = {}

function helpers.assert_eq(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. "\nexpected: " .. tostring(expected) .. "\nactual: " .. tostring(actual))
  end
end

function helpers.assert_contains(haystack, needle, message)
  if tostring(haystack):find(tostring(needle), 1, true) == nil then
    error(message or ("expected to find `" .. tostring(needle) .. "`"))
  end
end

function helpers.fixture_path(name)
  return common.resolve_path(common.current_dir(), "tests/fixtures/" .. tostring(name or ""))
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
