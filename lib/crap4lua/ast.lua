-- Lua AST access via luacheck (runtime dependency, installed through
-- LuaRocks). Provides function-boundary extraction and cyclomatic
-- complexity, replacing the old `luac -p -l` bytecode analysis (ADR-0001).
local ast = {}

local ok_decoder, decoder = pcall(require, "luacheck.decoder")
local ok_parser, parser = pcall(require, "luacheck.parser")

if not ok_decoder or not ok_parser then
  error("luacheck required: luarocks install luacheck", 0)
end

function ast.parse_source(source)
  local ok, parsed = pcall(parser.parse, decoder.decode(source))
  if not ok then
    return nil, tostring(parsed)
  end
  if not parsed then
    return nil, "parse error"
  end
  return parsed
end

function ast.parse_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil, "cannot open " .. path
  end
  local source = file:read("*a")
  file:close()
  return ast.parse_source(source)
end

local function _target_name(target)
  if type(target) ~= "table" then
    return nil
  end
  if target.tag == "Id" then
    return target[1]
  end
  if target.tag == "Index" then
    local left = _target_name(target[1])
    local key = target[2]
    local right = type(key) == "table" and (key.tag == "Id" or key.tag == "String") and key[1] or nil
    if left and right then
      return left .. "." .. right
    end
  end
  return nil
end

-- A named function declaration appears as the sole expression of a
-- Set/Localrec statement. The Function node's parent is the expression
-- array, so the statement itself is the grandparent.
local function _declared_name(grandparent)
  if type(grandparent) ~= "table" then
    return nil
  end
  local tag = grandparent.tag
  if tag ~= "Set" and tag ~= "Localrec" then
    return nil
  end
  local targets, exprs = grandparent[1], grandparent[2]
  if type(targets) ~= "table" or type(exprs) ~= "table" then
    return nil
  end
  if #targets ~= 1 or #exprs ~= 1 then
    return nil
  end
  return _target_name(targets[1])
end

local LOOP_TAGS = {
  While = true,
  Repeat = true,
  Fornum = true,
  Forin = true,
}

-- Cyclomatic complexity of one function body: 1 + decision points.
-- Decision points follow the upstream notion (conditionals and boolean
-- short-circuits): each If branch (incl. elseif), each loop, each and/or.
-- Nested Function subtrees are excluded — their complexity is their own.
local function _decisions(node)
  if type(node) ~= "table" then
    return 0
  end
  if node.tag == "Function" then
    return 0
  end
  local count = 0
  if node.tag == "If" then
    -- If{cond1, block1, cond2, block2, ..., else_block?}: one decision per
    -- condition; an else-only tail adds nothing.
    count = math.floor(#node / 2)
  elseif LOOP_TAGS[node.tag] then
    count = 1
  elseif node.tag == "Op" and (node[1] == "and" or node[1] == "or") then
    count = 1
  end
  for _, child in ipairs(node) do
    count = count + _decisions(child)
  end
  return count
end

local function _body_decisions(function_node)
  local count = 0
  for _, child in ipairs(function_node) do
    count = count + _decisions(child)
  end
  return count
end

local function _walk_functions(node, parent, grandparent, entries, source_path)
  if type(node) ~= "table" then
    return
  end
  if node.tag == "Function" then
    local start_line = node.line or 0
    local end_line = node.end_range and node.end_range.line or start_line
    entries[#entries + 1] = {
      name = _declared_name(grandparent) or ("function:" .. tostring(start_line)),
      source_path = source_path,
      start_line = start_line,
      end_line = end_line,
      complexity = 1 + _body_decisions(node),
    }
    -- Still descend: nested functions are units of their own.
  end
  for _, child in ipairs(node) do
    if type(child) == "table" then
      _walk_functions(child, node, parent, entries, source_path)
    end
  end
end

-- Returns an array of { name, source_path, start_line, end_line, complexity }
-- for every Function node in the chunk (named and anonymous, top-level and
-- nested).
function ast.extract_functions(chunk, source_path)
  local entries = {}
  for _, statement in ipairs(chunk) do
    _walk_functions(statement, nil, nil, entries, source_path)
  end
  return entries
end

function ast.analyze_file(abs_path)
  local chunk, err = ast.parse_file(abs_path)
  if not chunk then
    return nil, err
  end
  return ast.extract_functions(chunk, abs_path)
end

return ast
