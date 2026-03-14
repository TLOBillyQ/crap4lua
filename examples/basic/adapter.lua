local function normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function parent_dir(path)
  local normalized = normalize_path(path)
  return normalized:match("^(.*)/[^/]+$") or "."
end

local function join_path(left, right)
  local prefix = normalize_path(left):gsub("/+$", "")
  local suffix = normalize_path(right):gsub("^/+", "")
  if prefix == "" or prefix == "." then
    return suffix
  end
  if suffix == "" then
    return prefix
  end
  return prefix .. "/" .. suffix
end

local function adapter_root()
  local source = debug.getinfo(1, "S").source or ""
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  return parent_dir(source)
end

local project_root = adapter_root()

local function run_all(suites, opts)
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
    local sample = assert(loadfile(join_path(project_root, "src/sample.lua")))()
    return {
      {
        name = "example." .. tostring(lane),
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
    }, mode or "example"
  end,
  run = run_all,
  debug_api = debug,
}
