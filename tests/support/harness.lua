require("tests.support.bootstrap")

local function normalize_suite(suite, suite_index)
  if suite and suite.tests then
    return suite.name or ("suite_" .. tostring(suite_index)), suite.tests
  end
  return "suite_" .. tostring(suite_index), suite or {}
end

local function normalize_case(test, case_index, suite_name)
  if type(test) == "function" then
    return "case_" .. tostring(case_index), test, {}
  end
  if type(test) == "table" and type(test.run) == "function" then
    return test.name or ("case_" .. tostring(case_index)), test.run, test
  end
  error("invalid test case in " .. tostring(suite_name) .. " at index " .. tostring(case_index))
end

local function _run_hook(hook, ...)
  if type(hook) ~= "function" then
    return true
  end
  local args = { ... }
  return xpcall(function()
    hook(table.unpack(args))
  end, debug.traceback)
end

local function run_all(suites, opts)
  opts = opts or {}
  local total = 0
  local failures = {}

  for suite_index, suite in ipairs(suites) do
    local suite_name, tests = normalize_suite(suite, suite_index)
    for case_index, test in ipairs(tests) do
      local case_name, run, case_opts = normalize_case(test, case_index, suite_name)
      total = total + 1
      local context = {
        suite_name = suite_name,
        case_name = case_name,
        full_name = suite_name .. "." .. case_name,
        case_opts = case_opts,
      }
      local before_ok, before_err = _run_hook(opts.before_case, context)
      local ok = before_ok
      local err = before_err
      if before_ok then
        ok, err = xpcall(run, debug.traceback)
      end
      local after_ok, after_err = _run_hook(opts.after_case, context, ok, err, { lines = {} })
      if ok and not after_ok then
        ok = false
        err = after_err
      end
      if ok then
        io.stdout:write(".")
      else
        io.stdout:write("F")
        failures[#failures + 1] = {
          name = context.full_name,
          err = err,
        }
      end
    end
  end

  io.stdout:write("\n")
  if #failures > 0 then
    print("Tests failed (" .. tostring(#failures) .. "/" .. tostring(total) .. ")")
    for index, failure in ipairs(failures) do
      print(tostring(index) .. ") " .. failure.name)
      print(failure.err)
    end
    if opts.raise_on_failure ~= false then
      error("test run failed")
    end
  else
    print("All tests passed (" .. tostring(total) .. ")")
  end

  return {
    total = total,
    failures = failures,
    failed = #failures > 0,
  }
end

return {
  run_all = run_all,
}
