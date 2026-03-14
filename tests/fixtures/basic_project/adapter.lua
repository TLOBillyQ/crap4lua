local common = require("crap4lua.common")

local function _adapter_root()
  local source = debug.getinfo(1, "S").source or ""
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  return common.parent_dir(common.normalize_path(source)) or "."
end

local project_root = _adapter_root()

local function _run_all(suites, opts)
  local total = 0
  local failures = {}

  for _, suite in ipairs(suites or {}) do
    for _, test in ipairs(suite.tests or {}) do
      total = total + 1
      if type(opts.before_case) == "function" then
        opts.before_case({ full_name = suite.name .. "." .. test.name })
      end
      local ok, err = xpcall(test.run, debug.traceback)
      if type(opts.after_case) == "function" then
        opts.after_case({ full_name = suite.name .. "." .. test.name }, ok, err, { lines = {} })
      end
      if not ok then
        failures[#failures + 1] = {
          name = suite.name .. "." .. test.name,
          err = err,
        }
      end
    end
  end

  return {
    total = total,
    failures = failures,
    failed = #failures > 0,
  }
end

return {
  resolve_suites = function(lane, mode)
    local sample = assert(loadfile(common.join_path(project_root, "src/sample.lua")))()
    return {
      {
        name = "fixture." .. tostring(lane),
        tests = {
          {
            name = "truthy",
            run = function()
              assert(sample.run(true) == 4)
            end,
          },
          {
            name = "falsy",
            run = function()
              assert(sample.run(false) == 3)
            end,
          },
        },
      },
    }, mode or "fixture"
  end,
  run = _run_all,
  debug_api = debug,
}
