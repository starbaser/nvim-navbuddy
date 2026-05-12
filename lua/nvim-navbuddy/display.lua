local navic = require("nvim-navic.lib")

local ui = require("nvim-navbuddy.ui")

local ns = vim.api.nvim_create_namespace("nvim-navbuddy")

local function resolve_pct(spec, total)
  if type(spec) == "number" then
    return spec
  end
  if type(spec) == "string" then
    local pct = spec:match("^(%d+)%%$")
    if pct then
      return math.floor(total * tonumber(pct) / 100)
    end
    local int = spec:match("^(%d+)$")
    if int then
      return tonumber(int)
    end
  end
  error("navbuddy: invalid size " .. vim.inspect(spec))
end

local function configure_pane(winid, section_cfg, opts)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  if opts.filetype then
    vim.bo[bufnr].filetype = opts.filetype
  end
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].wrap = true
  vim.wo[winid].cursorline = false
  vim.wo[winid].winhighlight = "Normal:NavbuddyNormalFloat"
  vim.wo[winid].winfixheight = true
  vim.wo[winid].winfixwidth = true
  for k, v in pairs(section_cfg.win_options or {}) do
    vim.wo[winid][k] = v
  end
  for k, v in pairs(section_cfg.buf_options or {}) do
    vim.bo[bufnr][k] = v
  end
  return { winid = winid, bufnr = bufnr }
end

local function clear_buffer(pane)
  vim.api.nvim_win_set_buf(pane.winid, pane.bufnr)

  vim.wo[pane.winid].signcolumn = "no"
  vim.wo[pane.winid].foldlevel = 100
  vim.wo[pane.winid].wrap = true

  vim.bo[pane.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(pane.bufnr, 0, -1, false, {})
  vim.bo[pane.bufnr].modifiable = false
  for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(pane.bufnr, ns, 0, -1, {})) do
    vim.api.nvim_buf_del_extmark(pane.bufnr, ns, extmark[1])
  end
end

local function fill_buffer(pane, node, config)
  local cursor_pos = vim.api.nvim_win_get_cursor(pane.winid)
  clear_buffer(pane)

  local parent = node.parent

  local lines = {}
  for _, child_node in ipairs(parent.children) do
    local text = " " .. config.icons[child_node.kind] .. child_node.name
    table.insert(lines, text)
  end

  vim.bo[pane.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(pane.bufnr, 0, -1, false, lines)
  vim.bo[pane.bufnr].modifiable = false

  if cursor_pos[1] ~= node.index then
    cursor_pos[1] = node.index
  end

  for i, child_node in ipairs(parent.children) do
    local hl_group = "Navbuddy" .. navic.adapt_lsp_num_to_str(child_node.kind)
    vim.hl.range(pane.bufnr, ns, hl_group, { i - 1, 0 }, { i - 1, -1 })
    if config.node_markers.enabled then
      vim.api.nvim_buf_set_extmark(pane.bufnr, ns, i - 1, #lines[i], {
        virt_text = {
          {
            child_node.children ~= nil and config.node_markers.icons.branch
              or i == cursor_pos[1] and config.node_markers.icons.leaf_selected
              or config.node_markers.icons.leaf,
            i == cursor_pos[1] and { "NavbuddyCursorLine", hl_group } or hl_group,
          },
        },
        virt_text_pos = "right_align",
        virt_text_hide = false,
      })
    end
  end

  vim.hl.range(pane.bufnr, ns, "NavbuddyCursorLine", { cursor_pos[1] - 1, 0 }, { cursor_pos[1] - 1, -1 })
  vim.api.nvim_buf_set_extmark(pane.bufnr, ns, cursor_pos[1] - 1, #lines[cursor_pos[1]], {
    end_row = cursor_pos[1],
    hl_eol = true,
    hl_group = "NavbuddyCursorLine" .. navic.adapt_lsp_num_to_str(node.kind),
  })
  vim.api.nvim_win_set_cursor(pane.winid, cursor_pos)
end

---@private
---@class Navbuddy.display.opts
---@field config Navbuddy.config
---@field for_buf number
---@field for_win number
---@field start_cursor integer[] # (row, col) tuple
---@field focus_node Navbuddy.symbolNode
---@field lsp_name string

---@private
---@class Navbuddy.display.state
---@field leaving_window_for_action boolean
---@field leaving_window_for_reorientation boolean
---@field closed boolean
---@field original_win integer
---@field source_buffer_scrolloff? number
---@field user_gui_cursor? string

---@private
---@class Navbuddy.display
---@field config Navbuddy.config
---@field lsp_name string
---@field for_buf number
---@field for_win number
---@field start_cursor integer[] # (row, col) tuple
---@field focus_node Navbuddy.symbolNode
---@field left Navbuddy.pane
---@field mid Navbuddy.pane
---@field state Navbuddy.display.state
---@overload fun(opts:Navbuddy.display.opts): Navbuddy.display
local display = setmetatable({}, {
  __call = function(t, ...)
    return t.new(...)
  end,
})
display.__index = display

---@param opts Navbuddy.display.opts|Navbuddy.display
---@return Navbuddy.display
function display.new(opts)
  local self = setmetatable({}, display --[[@as metatable]])
  self.config = opts.config
  self.lsp_name = opts.lsp_name
  self.for_buf = opts.for_buf
  self.for_win = opts.for_win
  self.start_cursor = opts.start_cursor
  self.focus_node = opts.focus_node
  self.state = {
    leaving_window_for_action = false,
    leaving_window_for_reorientation = false,
    closed = false,
    original_win = vim.api.nvim_get_current_win(),
  }

  local strip_height = resolve_pct(self.config.window.height, vim.o.lines)
  local left_width = resolve_pct(self.config.window.sections.left.width, vim.o.columns)

  vim.api.nvim_set_current_win(self.for_win)

  vim.cmd("rightbelow " .. strip_height .. "split")
  local mid_win = vim.api.nvim_get_current_win()

  vim.cmd("leftabove " .. left_width .. "vsplit")
  local left_win = vim.api.nvim_get_current_win()

  self.left = configure_pane(left_win, self.config.window.sections.left, {})
  self.mid = configure_pane(mid_win, self.config.window.sections.mid, { filetype = "Navbuddy" })

  vim.api.nvim_set_current_win(self.mid.winid)

  display.init(self)
  return self
end

function display:init()
  ui.highlight_setup(self.config)

  if self.state.user_gui_cursor == nil then
    self.state.user_gui_cursor = vim.o.guicursor
  end
  if self.state.user_gui_cursor ~= "" then
    vim.o.guicursor = "a:NavbuddyCursor"
  end

  if self.config.source_buffer.scrolloff then
    self.state.source_buffer_scrolloff = vim.o.scrolloff
    vim.o.scrolloff = self.config.source_buffer.scrolloff
  end

  if self.config.window.scrolloff then
    vim.wo[self.mid.winid].scrolloff = self.config.window.scrolloff
  end

  local augroup = vim.api.nvim_create_augroup("Navbuddy", { clear = false })
  vim.api.nvim_clear_autocmds({ buffer = self.mid.bufnr })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = self.mid.bufnr,
    callback = function()
      local cursor_pos = vim.api.nvim_win_get_cursor(self.mid.winid)
      if self.focus_node ~= self.focus_node.parent.children[cursor_pos[1]] then
        self.focus_node = self.focus_node.parent.children[cursor_pos[1]]
        self:redraw()
      end

      self.focus_node.parent.memory = self.focus_node.index

      self:clear_highlights()
      self:focus_range()
    end,
  })
  vim.api.nvim_create_autocmd("BufLeave", {
    group = augroup,
    buffer = self.mid.bufnr,
    callback = function()
      if
        self.state.leaving_window_for_action == false
        and self.state.leaving_window_for_reorientation == false
        and self.state.closed == false
      then
        self:close()
      end
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = augroup,
    buffer = self.mid.bufnr,
    callback = function()
      vim.o.guicursor = self.state.user_gui_cursor
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = augroup,
    buffer = self.mid.bufnr,
    callback = function()
      if self.state.user_gui_cursor ~= "" then
        vim.o.guicursor = "a:NavbuddyCursor"
      end
    end,
  })

  for lhs, mapping in pairs(self.config.mappings) do
    vim.keymap.set("n", lhs, function()
      mapping.callback(self)
    end, { buffer = self.mid.bufnr, nowait = true })
  end

  self:redraw()
  self:focus_range()
  return self
end

function display:focus_range()
  local ranges = nil

  if vim.deep_equal(self.focus_node.scope, self.focus_node.name_range) then
    ranges = { { "NavbuddyScope", self.focus_node.scope } }
  else
    ranges = { { "NavbuddyScope", self.focus_node.scope }, { "NavbuddyName", self.focus_node.name_range } }
  end

  if self.config.source_buffer.highlight then
    for _, v in ipairs(ranges) do
      local highlight = v[1] --[[@as string]]
      local range = v[2] --[[@as Range]]
      vim.hl.range(
        self.for_buf,
        ns,
        highlight,
        { range["start"].line - 1, range["start"].character },
        { range["end"].line - 1, range["end"].character }
      )
    end
  end

  if self.config.source_buffer.follow_node then
    self:reorient(self.for_win, self.config.source_buffer.reorient)
  end
end

function display:reorient(ro_win, reorient_method)
  vim.api.nvim_win_set_cursor(
    ro_win,
    { self.focus_node.name_range["start"].line, self.focus_node.name_range["start"].character }
  )

  self.state.leaving_window_for_reorientation = true
  vim.api.nvim_set_current_win(ro_win)

  if reorient_method == "smart" then
    local total_lines = self.focus_node.scope["end"].line - self.focus_node.scope["start"].line + 1

    if total_lines >= vim.api.nvim_win_get_height(ro_win) then
      vim.api.nvim_command("normal! zt")
    else
      local mid_line = bit.rshift(self.focus_node.scope["start"].line + self.focus_node.scope["end"].line, 1)
      vim.api.nvim_win_set_cursor(ro_win, { mid_line, 0 })
      vim.api.nvim_command("normal! zz")
      vim.api.nvim_win_set_cursor(
        ro_win,
        { self.focus_node.name_range["start"].line, self.focus_node.name_range["start"].character }
      )
    end
  elseif reorient_method == "mid" then
    vim.api.nvim_command("normal! zz")
  elseif reorient_method == "top" then
    vim.api.nvim_command("normal! zt")
  end

  vim.api.nvim_set_current_win(self.mid.winid)
  self.state.leaving_window_for_reorientation = false
end

function display:clear_highlights()
  vim.api.nvim_buf_clear_namespace(self.for_buf, ns, 0, -1)
end

function display:redraw()
  local node = self.focus_node
  fill_buffer(self.mid, node, self.config)
  if node.parent.is_root then
    clear_buffer(self.left)
  else
    fill_buffer(self.left, node.parent, self.config)
  end
end

function display:close()
  self.state.closed = true
  vim.o.guicursor = self.state.user_gui_cursor
  if self.state.source_buffer_scrolloff then
    vim.o.scrolloff = self.state.source_buffer_scrolloff
  end
  self:clear_highlights()

  for _, pane in ipairs({ self.mid, self.left }) do
    if vim.api.nvim_win_is_valid(pane.winid) then
      vim.api.nvim_win_close(pane.winid, true)
    end
  end

  if vim.api.nvim_win_is_valid(self.state.original_win) then
    vim.api.nvim_set_current_win(self.state.original_win)
  end
end

return display
