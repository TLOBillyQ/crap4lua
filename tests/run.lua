-- Test entry point (ADR-0005: 4lua 工具链统一 luaunit): discovers
-- tests/unit/test_*.lua, loads each file's returned luaunit test table
-- (methods named test_*), and runs them all in a single luaunit suite.
-- Usage: `lua tests/run.lua`（依赖经 LUA_PATH 注入，见 Makefile）。

local function script_dir()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  source = source:gsub("\\", "/")
  if source:sub(1, 1) ~= "/" then
    local pipe = assert(io.popen("pwd", "r"))
    source = pipe:read("*l") .. "/" .. source
    pipe:close()
  end
  return source:match("^(.*)/[^/]+$") or "."
end

local test_root = script_dir()
local project_root = test_root:match("^(.*)/[^/]+$") or "."

package.path = table.concat({
  project_root .. "/?.lua",
  project_root .. "/?/init.lua",
  project_root .. "/src/?.lua",
  project_root .. "/src/?/init.lua",
  package.path,
}, ";")

local bootstrap = require("tests.support.bootstrap")
bootstrap.install_package_paths()

local function fail(message)
  io.stderr:write(tostring(message) .. "\n")
  os.exit(1)
end

local pipe = assert(io.popen('find "' .. test_root .. '/unit" -type f -name "test_*.lua"', "r"))
local files = {}
for line in pipe:lines() do
  files[#files + 1] = line
end
pipe:close()
table.sort(files)

if #files == 0 then
  fail("no test files discovered under " .. test_root .. "/unit")
end

local instances = {}
for _, file in ipairs(files) do
  local chunk, load_err = loadfile(file)
  if not chunk then
    fail("failed to load " .. file .. ": " .. tostring(load_err))
  end
  local ok, suite = pcall(chunk)
  if not ok then
    fail("failed to execute " .. file .. ": " .. tostring(suite))
  end
  if type(suite) ~= "table" then
    fail(file .. " did not return a luaunit test table")
  end
  instances[#instances + 1] = { file:match("([^/]+)%.lua$"), suite }
end

local lu = require("luaunit")
local runner = lu.LuaUnit.new()
os.exit(runner:runSuiteByInstancesNoCmdLineParsing(instances) > 0 and 1 or 0)
