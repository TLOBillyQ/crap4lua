local cli = require("crap4lua.cli")

local M = {}

function M.run(args, env)
  env = env or {}
  env.module_root = env.module_root or "."
  env.asset_root = env.asset_root or "./viewer"
  env.default_project_root = env.default_project_root or "."
  return cli.run(args or arg or {}, env)
end

function M.main()
  return M.run(arg or {})
end

if ... == nil then
  M.main()
else
  return M
end
