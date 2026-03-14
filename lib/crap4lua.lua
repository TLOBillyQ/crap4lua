local cli = require("crap4lua.cli")

local M = {}

function M.run(args, env)
  return cli.run(args or arg or {}, env or {})
end

function M.main()
  return M.run(arg or {})
end

if ... == nil then
  M.main()
else
  return M
end
