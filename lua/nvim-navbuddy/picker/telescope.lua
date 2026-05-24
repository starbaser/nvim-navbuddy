local M = {}
local defaultOpts = {
  layout_strategy = "horizontal",
  layout_config = {
    height = 0.60,
    width = 0.60,
    prompt_position = "top",
    preview_width = 0.50,
  },
}

---@private
---@param opts any
---@param display Navbuddy.display
M.find = function(opts, display)
  local status_ok, _ = pcall(require, "telescope")
  if not status_ok then
    vim.notify("telescope.nvim not found", vim.log.levels.ERROR)
    return
  end

  local navic = require("nvim-navic.lib")
  local pickers = require("telescope.pickers")
  local entry_display = require("telescope.pickers.entry_display")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local t_actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  opts = vim.tbl_extend("force", defaultOpts, opts or {})

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 14 },
      { remaining = true },
    },
  })

  local function make_display(entry)
    local node = entry.value
    local kind = navic.adapt_lsp_num_to_str(node.kind)
    local kind_hl = "Navbuddy" .. kind
    local name_hl = "NavbuddyNormalFloat"
    local columns = {
      { string.lower(kind), kind_hl },
      { node.name, name_hl },
    }
    return displayer(columns)
  end

  local function make_entry(node)
    local filename = node.filename or vim.api.nvim_buf_get_name(display.for_buf)
    return {
      value = node,
      display = make_display,
      name = node.name,
      ordinal = string.lower(navic.adapt_lsp_num_to_str(node.kind)) .. " " .. node.name,
      lnum = node.name_range["start"].line,
      col = node.name_range["start"].character,
      bufnr = node.bufnr or display.for_buf,
      filename = filename,
    }
  end

  display:close()
  pickers
    .new(opts, {
      prompt_title = "Navbuddy",
      finder = finders.new_table({
        results = display.focus_node.parent.children,
        entry_maker = make_entry,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = conf.qflist_previewer(opts),
      attach_mappings = function(prompt_bufnr, _)
        t_actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          display.focus_node = selection.value
          t_actions.close(prompt_bufnr)
        end)
        vim.api.nvim_create_autocmd("BufWipeout", {
          buffer = prompt_bufnr,
          once = true,
          callback = function()
            vim.schedule(function()
              display = require("nvim-navbuddy.display").new(display)
            end)
          end,
        })
        return true
      end,
    })
    :find()
end

return M
