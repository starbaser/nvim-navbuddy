---@text HIGHLIGHT
---
--- |nvim-navbuddy| provides the following highlights which get used when
--- available.
---
--- `NavbuddyName`  - highlight for name in source buffer
--- `NavbuddyScope` - highlight for scope of context in source buffer
--- `NavbuddyFloatBorder` - Floatborder highlight
--- `NavbuddyNormalFloat` - Float normal highlight
---
--- The following highlights are are used to highlight elements in the navbuddy
--- window according to their type. If you have "NavicIcons<type>" highlights
--- already defined, these will automatically get linked to them unless defined
--- explicitly.
---
--- `NavbuddyFile`
--- `NavbuddyModule`
--- `NavbuddyNamespace`
--- `NavbuddyPackage`
--- `NavbuddyClass`
--- `NavbuddyMethod`
--- `NavbuddyProperty`
--- `NavbuddyField`
--- `NavbuddyConstructor`
--- `NavbuddyEnum`
--- `NavbuddyInterface`
--- `NavbuddyFunction`
--- `NavbuddyVariable`
--- `NavbuddyConstant`
--- `NavbuddyString`
--- `NavbuddyNumber`
--- `NavbuddyBoolean`
--- `NavbuddyArray`
--- `NavbuddyObject`
--- `NavbuddyKey`
--- `NavbuddyNull`
--- `NavbuddyEnumMember`
--- `NavbuddyStruct`
--- `NavbuddyEvent`
--- `NavbuddyOperator`
--- `NavbuddyTypeParameter`
---@tag navbuddy-highlights
---@toc_entry Highlights

local navic = require("nvim-navic.lib")

local ui = {}

---@private
---@param config Navbuddy.config
function ui.highlight_setup(config)
  for lsp_num = 1, 26 do
    local navbuddy_name = "Navbuddy" .. navic.adapt_lsp_num_to_str(lsp_num)
    local cursorline_name = "NavbuddyCursorLine" .. navic.adapt_lsp_num_to_str(lsp_num)

    local navbuddy_hl_def = vim.api.nvim_get_hl(0, { name = navbuddy_name })
    local navic_hl_def = vim.api.nvim_get_hl(0, { name = "NavicIcons" .. navic.adapt_lsp_num_to_str(lsp_num) })

    if vim.tbl_isempty(navbuddy_hl_def) and not vim.tbl_isempty(navic_hl_def) then
      vim.api.nvim_set_hl(0, navbuddy_name, { fg = navic_hl_def.fg })
    end

    local effective_hl = vim.api.nvim_get_hl(0, { name = navbuddy_name })
    local fg = effective_hl.fg
    if fg == nil then
      fg = vim.api.nvim_get_hl(0, { name = "Normal" }).fg
      vim.api.nvim_set_hl(0, navbuddy_name, { fg = fg })
    end

    local cursorline_def
    if config.custom_hl_group ~= nil then
      cursorline_def = { link = config.custom_hl_group }
    else
      cursorline_def = { bg = fg }
    end
    vim.api.nvim_set_hl(0, cursorline_name, cursorline_def)
  end

  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "NavbuddyCursorLine" })) then
    local cursorline_def
    if config.custom_hl_group ~= nil then
      cursorline_def = { link = config.custom_hl_group }
    else
      cursorline_def = { reverse = true, bold = true }
    end
    vim.api.nvim_set_hl(0, "NavbuddyCursorLine", cursorline_def)
  end

  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "NavbuddyCursor" })) then
    vim.api.nvim_set_hl(0, "NavbuddyCursor", { bg = "#000000", blend = 100 })
  end

  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "NavbuddyName" })) then
    vim.api.nvim_set_hl(0, "NavbuddyName", { link = "IncSearch" })
  end

  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "NavbuddyScope" })) then
    vim.api.nvim_set_hl(0, "NavbuddyScope", { link = "Visual" })
  end

  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "NavbuddyFloatBorder" })) then
    vim.api.nvim_set_hl(0, "NavbuddyFloatBorder", { link = "FloatBorder" })
  end

  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "NavbuddyNormalFloat" })) then
    vim.api.nvim_set_hl(0, "NavbuddyNormalFloat", { link = "NormalFloat" })
  end
end

return ui
