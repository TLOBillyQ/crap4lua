local source_names = {}

local function _append_name(names_by_line, line_no, name)
  if line_no == nil or name == nil or name == "" then
    return
  end
  local bucket = names_by_line[line_no]
  if bucket == nil then
    bucket = {}
    names_by_line[line_no] = bucket
  end
  bucket[#bucket + 1] = name
end

function source_names.extract(source_text)
  local names_by_line = {}
  local line_no = 0
  for line in (tostring(source_text or "") .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    _append_name(names_by_line, line_no, line:match("^%s*local%s+function%s+([%w_]+)%s*%("))
    _append_name(names_by_line, line_no, line:match("^%s*function%s+([%w_%.:]+)%s*%("))
    _append_name(names_by_line, line_no, line:match("^%s*([%w_%.]+)%s*=%s*function%s*%("))
  end
  return names_by_line
end

function source_names.consume_name(names_by_line, line_no)
  local bucket = names_by_line and names_by_line[line_no]
  if bucket == nil or #bucket == 0 then
    return nil
  end
  local name = bucket[1]
  table.remove(bucket, 1)
  return name
end

return source_names
