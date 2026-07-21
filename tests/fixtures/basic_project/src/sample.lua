local sample = {}

local function alpha(flag)
  if flag then
    return 1
  end
  return 0
end

function sample.beta(n)
  local total = 0
  for i = 1, n do
    total = total + i
  end
  return total
end

function sample.run(flag)
  return alpha(flag) + sample.beta(2)
end

return sample
