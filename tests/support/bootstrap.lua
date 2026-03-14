local M = {}

local _installed = false

local function _append_path(path_pattern)
  if not tostring(package.path):find(path_pattern, 1, true) then
    package.path = path_pattern .. ";" .. package.path
  end
end

function M.install_package_paths()
  if _installed then
    return
  end
  _append_path("./tests/?/?/?.lua")
  _append_path("./tests/?/?.lua")
  _append_path("./tests/?.lua")
  _append_path("./lib/?/?.lua")
  _append_path("./lib/?.lua")
  _installed = true
end

M.install_package_paths()

return M
