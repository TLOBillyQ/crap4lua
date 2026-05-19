local function is_absolute(path)
  path = tostring(path or "")
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

local function normalize(path)
  path = tostring(path or ""):gsub("\\", "/")
  local prefix = ""
  if path:sub(1, 1) == "/" then
    prefix = "/"
    path = path:sub(2)
  elseif path:match("^%a:/") then
    prefix = path:sub(1, 3)
    path = path:sub(4)
  end
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then
        parts[#parts] = nil
      elseif prefix == "" then
        parts[#parts + 1] = part
      end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  local joined = table.concat(parts, "/")
  if prefix == "" then
    return joined == "" and "." or joined
  end
  return joined == "" and prefix:gsub("/$", "") or (prefix .. joined)
end

local function current_dir()
  local pwd = os.getenv("PWD")
  if pwd and pwd ~= "" then
    return pwd
  end
  local handle = assert(io.popen("pwd", "r"))
  local output = handle:read("*l")
  handle:close()
  return output
end

local function dirname(path)
  path = normalize(path):gsub("/+$", "")
  return path:match("^(.*)/[^/]+$") or "."
end

local function script_path()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  if not is_absolute(source) then
    source = current_dir() .. "/" .. source
  end
  return normalize(source)
end

local test_root = dirname(script_path())
local project_root = dirname(test_root)

package.path = table.concat({
  project_root .. "/?.lua",
  project_root .. "/?/init.lua",
  project_root .. "/lib/?.lua",
  project_root .. "/lib/?/init.lua",
  package.path,
}, ";")

local bootstrap = require("tests.support.bootstrap")
local harness = require("tests.support.harness")

bootstrap.install_package_paths()

local suites = {
  require("tests.unit.test_bridge"),
  require("tests.unit.test_coverage"),
  require("tests.unit.test_config"),
}

harness.run_all(suites)
