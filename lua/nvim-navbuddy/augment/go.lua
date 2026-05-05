local M = {}

local ts = vim.treesitter
local SymbolKind = vim.lsp.protocol.SymbolKind

-- Compiled query for performance
local GO_QUERY = [[
  (method_declaration receiver: (parameter_list (parameter_declaration name: (identifier) @receiver (#not-eq? @receiver "_"))))
  (parameter_declaration name: (identifier) @param (#not-eq? @param "_"))
  (short_var_declaration left: (expression_list (identifier) @var (#not-eq? @var "_")))
  (var_declaration (var_spec name: (identifier) @var (#not-eq? @var "_")))
  (range_clause left: (expression_list (identifier) @var (#not-eq? @var "_")))
]]

--- Checks if a line/col is within a navic scope range (1-based line, 0-based col)
local function is_in_scope(scope, line, col)
  if not scope or not scope.start or not scope["end"] then
    return false
  end

  if line < scope.start.line or line > scope["end"].line then
    return false
  end
  if line == scope.start.line and col < scope.start.character then
    return false
  end
  if line == scope["end"].line and col > scope["end"].character then
    return false
  end

  return true
end

--- Recursively finds the deepest Function or Method node containing the TS node
local function find_enclosing_func_node(navic_node, line, col)
  local best_match = nil

  if navic_node.kind == SymbolKind.Function or navic_node.kind == SymbolKind.Method then
    if is_in_scope(navic_node.scope, line, col) then
      best_match = navic_node
    end
  end

  if navic_node.children then
    for _, child in ipairs(navic_node.children) do
      local child_match = find_enclosing_func_node(child, line, col)
      if child_match then
        best_match = child_match
      end
    end
  end

  return best_match
end

function M.augment(bufnr, root_node)
  local parser = ts.get_parser(bufnr, "go")
  if not parser then
    return root_node
  end

  local tree = parser:parse()[1]
  local root = tree:root()
  local query = ts.query.parse("go", GO_QUERY)

  -- Temporary table to hold children before linking
  -- Structure: func_node_ref -> { child1, child2, ... }
  local new_children_map = {}

  for _, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local start_row, start_col, end_row, end_col = node:range()
    local name = ts.get_node_text(node, bufnr)

    -- Convert TS 0-based to Navic 1-based line representation
    local start_line = start_row + 1
    local end_line = end_row + 1

    local parent_func = find_enclosing_func_node(root_node, start_line, start_col)

    if parent_func then
      local synthetic_node = {
        name = name,
        kind = SymbolKind.Variable, -- Using Variable for both locals and params for MVP
        name_range = {
          start = { line = start_line, character = start_col },
          ["end"] = { line = end_line, character = end_col },
        },
        scope = {
          start = { line = start_line, character = start_col },
          ["end"] = { line = end_line, character = end_col },
        },
        parent = parent_func,
        children = nil, -- Leaves
      }

      if not new_children_map[parent_func] then
        new_children_map[parent_func] = {}
      end
      table.insert(new_children_map[parent_func], synthetic_node)
    end
  end

  -- Wire up the doubly-linked list for navbuddy integration
  for parent_func, children in pairs(new_children_map) do
    parent_func.children = parent_func.children or {}

    -- Sort sequentially by appearance in file
    table.sort(children, function(a, b)
      if a.name_range.start.line == b.name_range.start.line then
        return a.name_range.start.character < b.name_range.start.character
      end
      return a.name_range.start.line < b.name_range.start.line
    end)

    for i, child in ipairs(children) do
      child.index = i
      child.prev = (i > 1) and children[i - 1] or nil
      child.next = (i < #children) and children[i + 1] or nil
      table.insert(parent_func.children, child)
    end
  end

  return root_node
end

return M
