local M = {}

--- Augments the navic symbol tree with treesitter data.
---@param bufnr number
---@param root_node table Navbuddy/navic symbolNode
---@param filetype string
---@return table root_node (mutated in place)
function M.augment(bufnr, root_node, filetype)
  if not root_node then
    return root_node
  end

  local ok, lang_mod = pcall(require, "nvim-navbuddy.augment." .. filetype)
  if not ok then
    return root_node
  end

  -- Wrap in pcall to ensure TS parser failures don't crash the UI
  local success, err = pcall(lang_mod.augment, bufnr, root_node)
  if not success then
    vim.notify_once("Navbuddy TS Augment Error: " .. tostring(err), vim.log.levels.WARN)
  end

  return root_node
end

return M
