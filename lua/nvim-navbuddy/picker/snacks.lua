local M = {}

---@private
---@param opts any
---@param display Navbuddy.display
function M.find(opts, display)
  local status_ok, snack_picker = pcall(require, "snacks.picker")
  if not status_ok then
    vim.notify("snacks.nvim not found", vim.log.levels.ERROR)
    return
  end

  local navic = require("nvim-navic.lib")

  ---@type snacks.picker.Config
  local picker_conf = {
    title = "Navbuddy",
    layout = {
      layout = {
        width = 0.6,
        height = 0.6,
        min_width = 90,
      },
    },
    finder = function()
      local items = {}

      for _, node in ipairs(display.focus_node.parent.children) do
        table.insert(items, {
          value = node,
          text = node.name,
          pos = { node.name_range["start"].line, node.name_range["start"].character },
          end_pos = { node.name_range["end"].line, node.name_range["end"].character },
          file = node.filename or vim.api.nvim_buf_get_name(display.for_buf),
        })
      end

      return items
    end,
    confirm = function(p, item)
      display.focus_node = item.value
      p:close()
    end,
    on_close = function()
      vim.schedule(function()
        require("nvim-navbuddy.display").new(display)
      end)
    end,
    format = function(item, _)
      local kind = navic.adapt_lsp_num_to_str(item.value.kind)
      local kind_hl = "Navbuddy" .. kind

      local ret = {} ---@type snacks.picker.Highlight[]
      ret[#ret + 1] = { Snacks.picker.util.align(tostring(kind), 15), kind_hl }
      ret[#ret + 1] = { item.text }
      return ret
    end,
  }

  opts = vim.tbl_extend("force", picker_conf, opts or {})
  snack_picker.pick(nil, opts)
end

return M
