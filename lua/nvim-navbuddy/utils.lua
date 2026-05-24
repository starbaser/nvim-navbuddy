local M = {}

---@param name string
---@param config Navbuddy.config
---@return boolean
function M.check_integration(name, config)
  local enabled = config.integrations[name]

  if enabled == nil or enabled == "auto" then
    local success, _ = pcall(require, name:gsub("_", "-"))
    return success
  end

  return enabled
end

---@param node Navbuddy.symbolNode
---@return boolean
function M.is_symbol_node(node)
  return node.node_type == nil or node.node_type == "symbol"
end

---@param node Navbuddy.symbolNode
---@return boolean
function M.is_container_node(node)
  return node.node_type == "directory" or node.node_type == "workspace"
end

---@param bufnr integer
function M.ensure_filetype(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].filetype ~= "" then
    return
  end

  local filetype = vim.filetype and vim.filetype.match({ buf = bufnr })
  vim.api.nvim_buf_call(bufnr, function()
    if filetype and filetype ~= "" then
      vim.cmd("setfiletype " .. filetype)
    else
      vim.cmd("silent! filetype detect")
    end
  end)
end

---@param bufnr integer
---@param cursor integer[]
---@return integer[]
function M.clamp_cursor(bufnr, cursor)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  return { math.min(math.max(cursor[1], 1), line_count), cursor[2] }
end

--- Re-write index/prev/next/parent on every entry in `parent.children`.
--- If `sort_fn` is provided, sort children first.
---@param parent Navbuddy.symbolNode
---@param sort_fn? fun(a: Navbuddy.symbolNode, b: Navbuddy.symbolNode): boolean
function M.relink_children(parent, sort_fn)
  local children = parent.children
  if not children then
    return
  end

  if sort_fn then
    table.sort(children, sort_fn)
  end

  for i, child in ipairs(children) do
    child.parent = parent
    child.index = i
    child.prev = children[i - 1]
    child.next = children[i + 1]
  end
end

return M
