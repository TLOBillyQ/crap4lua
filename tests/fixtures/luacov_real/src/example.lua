local example = {}

-- A simple 1-liner: CC=1, fully covered by tests.
function example.trivial()
  return 42
end

-- A branching function with partial coverage: the else branch is never taken.
function example.branchy(flag)
  if flag then
    return "yes"
  else
    return "no"
  end
end

-- A looping function with high coverage: loop runs 5 times.
function example.loopy(n)
  local total = 0
  for i = 1, n do
    total = total + i
  end
  return total
end

-- An intentionally uncovered function: never called, CRAP = N/A.
function example.untouched()
  if true then
    return "unreachable"
  else
    return "unreachable-too"
  end
end

return example
