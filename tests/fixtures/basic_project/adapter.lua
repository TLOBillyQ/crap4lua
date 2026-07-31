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
      local ok, err = xpcall(test.run, debug.traceback)
      if not ok then
        failures[#failures + 1] = {
          name = suite.name .. "." .. test.name,
          err = err,
        }
      end
    end
  end

  -- The fixture stands in for a luacov-instrumented run: it emits the
  -- standard report artifact the way `luacov`'s default reporter would.
  -- Both alpha branches, beta's loop, and run are exercised by the suites.
  if opts.report_path then
    local lines = {
      "==============================================================================",
      "src/sample.lua",
      "==============================================================================",
      "      2 local sample = {}",
      "        ",
      "      2 local function alpha(flag)",
      "      2   if flag then",
      "      1     return 1",
      "          end",
      "      1   return 0",
      "        end",
      "        ",
      "      2 function sample.beta(n)",
      "      2   local total = 0",
      "      2   for i = 1, n do",
      "      4     total = total + i",
      "          end",
      "      2   return total",
      "        end",
      "        ",
      "      2 function sample.run(flag)",
      "      2   return alpha(flag) + sample.beta(2)",
      "        end",
      "        ",
      "      1 return sample",
    }
    local file = assert(io.open(opts.report_path, "w"))
    file:write(table.concat(lines, "\n") .. "\n")
    file:close()
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
  run = run_all,
}
