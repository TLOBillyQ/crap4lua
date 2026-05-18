local common = require("shared.lib.common")

if not common.relative_to then
  function common.relative_to(base, source)
    local path = tostring(source or ""):gsub("\\", "/"):gsub("^@", "")
    local prefix = tostring(base or ""):gsub("\\", "/"):gsub("/+$", "") .. "/"
    if path:sub(1, #prefix) == prefix then
      return path:sub(#prefix + 1)
    end
    return path
  end
end

return common
