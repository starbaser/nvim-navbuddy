---@text ACTIONS
---
--- |nvim-navbuddy| provides the following actions for the user.
---@tag navbuddy-actions
---@toc_entry Actions

local utils = require("nvim-navbuddy.utils")
local actions = {}

local function is_symbol_node(node)
  return node.node_type == nil or node.node_type == "symbol"
end

local function is_container_node(node)
  return node.node_type == "directory" or node.node_type == "workspace"
end

local function notify_no_children(node)
  if node.node_type == "file" then
    vim.notify("Navbuddy found no symbols in " .. node.name, vim.log.levels.WARN)
  end
end

local function require_symbol(display)
  if not is_symbol_node(display.focus_node) then
    vim.notify("Navbuddy action only works on symbols", vim.log.levels.WARN)
    return nil
  end
  return display:focus_file(display.focus_node)
end

local function clamp_cursor(bufnr, cursor)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  return { math.min(math.max(cursor[1], 1), line_count), cursor[2] }
end

local function redraw(display)
  display:clear_highlights()
  display:redraw()
  display:focus_range()
end

local function reorient(winid, node, method)
  if not is_symbol_node(node) then
    vim.api.nvim_win_set_cursor(winid, { 1, 0 })
    vim.api.nvim_command("normal! zt")
    return
  end

  vim.api.nvim_win_set_cursor(winid, { node.name_range["start"].line, node.name_range["start"].character })

  if method == "smart" then
    local total_lines = node.scope["end"].line - node.scope["start"].line + 1

    if total_lines >= vim.api.nvim_win_get_height(winid) then
      vim.api.nvim_command("normal! zt")
    else
      local mid_line = bit.rshift(node.scope["start"].line + node.scope["end"].line, 1)
      vim.api.nvim_win_set_cursor(winid, { mid_line, 0 })
      vim.api.nvim_command("normal! zz")
      vim.api.nvim_win_set_cursor(winid, { node.name_range["start"].line, node.name_range["start"].character })
    end
  elseif method == "mid" then
    vim.api.nvim_command("normal! zz")
  elseif method == "top" then
    vim.api.nvim_command("normal! zt")
  end
end

local function select_node(display, split_cmd)
  local node = display.focus_node

  if is_container_node(node) then
    actions.children().callback(display)
    return
  end

  local bufnr = display:focus_file(node)
  if not bufnr then
    return
  end

  local target_win = display.for_win
  display:close()

  if not vim.api.nvim_win_is_valid(target_win) then
    return
  end

  vim.api.nvim_set_current_win(target_win)
  if split_cmd then
    vim.api.nvim_command(split_cmd)
    target_win = vim.api.nvim_get_current_win()
  end

  if vim.api.nvim_win_get_buf(target_win) ~= bufnr then
    vim.api.nvim_win_set_buf(target_win, bufnr)
  end

  vim.api.nvim_win_set_cursor(
    target_win,
    clamp_cursor(bufnr, { node.name_range["start"].line, node.name_range["start"].character })
  )
  vim.api.nvim_command("normal! m'")
  reorient(target_win, node, display.config.source_buffer.reorient)
end

local function fix_end_character_position(bufnr, name_range_or_scope)
  if
    name_range_or_scope["end"].character == 0
    and (name_range_or_scope["end"].line - name_range_or_scope["start"].line) > 0
  then
    name_range_or_scope["end"].line = name_range_or_scope["end"].line - 1
    name_range_or_scope["end"].character = string.len(
      vim.api.nvim_buf_get_lines(bufnr, name_range_or_scope["end"].line - 1, name_range_or_scope["end"].line, false)[1]
    )
  end
end

--- Close the Navbuddy window and return cursor to original location.
function actions.close()
  local callback = function(display)
    local target_win = display.for_win
    local start_buf = display.start_buf
    local start_cursor = display.start_cursor
    display:close()
    if vim.api.nvim_win_is_valid(target_win) and vim.api.nvim_buf_is_valid(start_buf) then
      vim.api.nvim_win_set_buf(target_win, start_buf)
      vim.api.nvim_win_set_cursor(target_win, clamp_cursor(start_buf, start_cursor))
    end
  end

  return {
    callback = callback,
    description = "Close Navbuddy",
  }
end

--- Move to next_sibling, below current node, in Navbuddy window.
function actions.next_sibling()
  local callback = function(display)
    if display.focus_node.next == nil then
      return
    end

    for _ = 1, vim.v.count1 do
      local next_node = display.focus_node.next
      if next_node == nil then
        break
      end
      display.focus_node = next_node
    end

    redraw(display)
  end

  return {
    callback = callback,
    description = "Move down to next node",
  }
end

--- Move to previous_sibling, above current node, in Navbuddy window.
function actions.previous_sibling()
  local callback = function(display)
    if display.focus_node.prev == nil then
      return
    end

    for _ = 1, vim.v.count1 do
      local prev_node = display.focus_node.prev
      if prev_node == nil then
        break
      end
      display.focus_node = prev_node
    end

    redraw(display)
  end

  return {
    callback = callback,
    description = "Move up to previous node",
  }
end

--- Move to parent of current, left of current node, in Navbuddy window.
function actions.parent()
  local callback = function(display)
    if display.focus_node.parent.is_root then
      return
    end

    local parent_node = display.focus_node.parent
    display.focus_node = parent_node

    redraw(display)
  end

  return {
    callback = callback,
    description = "Move left to parent level",
  }
end

--- Move to children of current, right of current node, in Navbuddy window.
function actions.children()
  local callback = function(display)
    if display.focus_node.node_type == "file" and not display.focus_node.symbols_loaded and display.workspace then
      local file_node = display.focus_node
      display.workspace:load_symbols(file_node, function()
        if display.state.closed then
          return
        end
        if file_node.children == nil then
          notify_no_children(file_node)
          return
        end
        actions.children().callback(display)
      end)
      return
    end

    if display.focus_node.children == nil then
      if display.focus_node.node_type == "file" then
        notify_no_children(display.focus_node)
        return
      end
      actions.select().callback(display)
      return
    end

    local child_node
    if display.focus_node.memory then
      child_node = display.focus_node.children[display.focus_node.memory]
    else
      child_node = display.focus_node.children[1]
    end
    display.focus_node = child_node

    redraw(display)
  end

  return {
    callback = callback,
    description = "Move right to child node level",
  }
end

--- Move to root node, the first node left of current node, in Navbuddy window.
function actions.root()
  local callback = function(display)
    if display.focus_node.parent.is_root then
      return
    end

    while not display.focus_node.parent.is_root do
      display.focus_node.parent.memory = display.focus_node.index
      display.focus_node = display.focus_node.parent
    end

    redraw(display)
  end

  return {
    callback = callback,
    description = "Move to top most node",
  }
end

--- Goto currently focus node.
function actions.select()
  local callback = function(display)
    if is_symbol_node(display.focus_node) then
      local bufnr = display:focus_file(display.focus_node)
      if bufnr then
        fix_end_character_position(bufnr, display.focus_node.name_range)
        fix_end_character_position(bufnr, display.focus_node.scope)
      end
    end
    select_node(display)
  end

  return {
    callback = callback,
    description = "Select and Goto current node",
  }
end

--- Yank the name of current node.
function actions.yank_name()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    display:close()
    fix_end_character_position(bufnr, display.focus_node.name_range)
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.name_range["start"].line, display.focus_node.name_range["start"].character }
    )
    vim.api.nvim_command("normal! v")
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.name_range["end"].line, display.focus_node.name_range["end"].character - 1 }
    )
    vim.api.nvim_command('normal! "+y')
  end

  return {
    callback = callback,
    description = "Yank node name",
  }
end

--- Yank the scope of current node.
function actions.yank_scope()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    display:close()
    fix_end_character_position(bufnr, display.focus_node.scope)
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.scope["start"].line, display.focus_node.scope["start"].character }
    )
    vim.api.nvim_command("normal! v")
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.scope["end"].line, display.focus_node.scope["end"].character - 1 }
    )
    vim.api.nvim_command('normal! "+y')
  end

  return {
    callback = callback,
    description = "Yank node scope",
  }
end

--- Visual select the name of current node.
function actions.visual_name()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    display:close()
    fix_end_character_position(bufnr, display.focus_node.name_range)
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.name_range["start"].line, display.focus_node.name_range["start"].character }
    )
    vim.api.nvim_command("normal! v")
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.name_range["end"].line, display.focus_node.name_range["end"].character - 1 }
    )
  end

  return {
    callback = callback,
    description = "Visual select node name",
  }
end

--- Visual select the scope of current node.
function actions.visual_scope()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    display:close()
    fix_end_character_position(bufnr, display.focus_node.scope)
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.scope["start"].line, display.focus_node.scope["start"].character }
    )
    vim.api.nvim_command("normal! v")
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.scope["end"].line, display.focus_node.scope["end"].character - 1 }
    )
  end

  return {
    callback = callback,
    description = "Visual select node scope",
  }
end

--- Start insert at begin of name.
function actions.insert_name()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    display:close()
    fix_end_character_position(bufnr, display.focus_node.name_range)
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.name_range["start"].line, display.focus_node.name_range["start"].character }
    )
    vim.api.nvim_feedkeys("i", "n", false)
  end

  return {
    callback = callback,
    description = "Insert node name",
  }
end

--- Start insert at begin of scope.
function actions.insert_scope()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    display:close()
    fix_end_character_position(bufnr, display.focus_node.scope)
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.scope["start"].line, display.focus_node.scope["start"].character }
    )
    vim.api.nvim_feedkeys("i", "n", false)
  end

  return {
    callback = callback,
    description = "Insert node scope",
  }
end

--- Start insert at end of name.
function actions.append_name()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    display:close()
    fix_end_character_position(bufnr, display.focus_node.name_range)
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.name_range["end"].line, display.focus_node.name_range["end"].character - 1 }
    )
    vim.api.nvim_feedkeys("a", "n", false)
  end

  return {
    callback = callback,
    description = "Append node name",
  }
end

--- Start insert at end of scope.
function actions.append_scope()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    display:close()
    fix_end_character_position(bufnr, display.focus_node.scope)
    if
      string.len(
        vim.api.nvim_buf_get_lines(
          bufnr,
          display.focus_node.scope["end"].line - 1,
          display.focus_node.scope["end"].line,
          false
        )[1]
      ) == display.focus_node.scope["end"].character
    then
      vim.api.nvim_win_set_cursor(
        display.for_win,
        { display.focus_node.scope["end"].line, display.focus_node.scope["end"].character }
      )
    else
      vim.api.nvim_win_set_cursor(
        display.for_win,
        { display.focus_node.scope["end"].line, display.focus_node.scope["end"].character - 1 }
      )
    end
    vim.api.nvim_feedkeys("a", "n", false)
  end

  return {
    callback = callback,
    description = "Append node scope",
  }
end

--- Trigger lsp rename for currently focused node.
function actions.rename()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    local target_win = display.for_win
    display:close()
    if vim.api.nvim_win_get_buf(target_win) ~= bufnr then
      vim.api.nvim_win_set_buf(target_win, bufnr)
    end
    vim.api.nvim_win_set_cursor(
      target_win,
      { display.focus_node.name_range["start"].line, display.focus_node.name_range["start"].character }
    )
    vim.api.nvim_set_current_win(target_win)
    vim.lsp.buf.rename()
  end

  return {
    callback = callback,
    description = "Rename",
  }
end

--- Delete currently focused scope.
function actions.delete()
  local callback = function(display)
    if not is_symbol_node(display.focus_node) then
      vim.notify("Navbuddy action only works on symbols", vim.log.levels.WARN)
      return
    end
    actions.visual_scope().callback(display)
    vim.api.nvim_command("normal! d")
  end

  return {
    callback = callback,
    description = "Delete",
  }
end

--- Create fold for current scope. Requires fold methos to be "manual".
function actions.fold_create()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    if vim.o.foldmethod ~= "manual" then
      vim.notify("Fold create action works only when foldmethod is 'manual'", vim.log.levels.ERROR)
      return
    end

    fix_end_character_position(bufnr, display.focus_node.scope)
    display.state.leaving_window_for_action = true
    vim.api.nvim_set_current_win(display.for_win)
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.scope["start"].line, display.focus_node.scope["start"].character }
    )
    vim.api.nvim_command("normal! v")
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.scope["end"].line, display.focus_node.scope["end"].character - 1 }
    )
    vim.api.nvim_command("normal! zf")
    vim.api.nvim_set_current_win(display.mid.winid)
    display.state.leaving_window_for_action = false
  end

  return {
    callback = callback,
    description = "Create fold",
  }
end

--- Delete fold for current scope. Requires fold methos to be "manual".
function actions.fold_delete()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    if vim.o.foldmethod ~= "manual" then
      vim.notify("Fold delete action works only when foldmethod is 'manual'", vim.log.levels.ERROR)
      return
    end

    fix_end_character_position(bufnr, display.focus_node.scope)
    display.state.leaving_window_for_action = true
    vim.api.nvim_set_current_win(display.for_win)
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.scope["start"].line, display.focus_node.scope["start"].character }
    )
    vim.api.nvim_command("normal! v")
    vim.api.nvim_win_set_cursor(
      display.for_win,
      { display.focus_node.scope["end"].line, display.focus_node.scope["end"].character - 1 }
    )
    pcall(vim.api.nvim_command, "normal! zd")
    vim.api.nvim_set_current_win(display.mid.winid)
    display.state.leaving_window_for_action = false
  end

  return {
    callback = callback,
    description = "Delete fold",
  }
end

--- Comment selected scope. Require Comment.nvim plugin to be installed.
function actions.comment()
  local callback = function(display)
    local bufnr = require_symbol(display)
    if not bufnr then
      return
    end
    local status_ok, comment = pcall(require, "Comment.api")
    if not status_ok then
      vim.notify("Comment.nvim not found", vim.log.levels.ERROR)
      return
    end

    fix_end_character_position(bufnr, display.focus_node.scope)
    display.state.leaving_window_for_action = true
    vim.api.nvim_set_current_win(display.for_win)
    vim.api.nvim_buf_set_mark(
      bufnr,
      "<",
      display.focus_node.scope["start"].line,
      display.focus_node.scope["start"].character,
      {}
    )
    vim.api.nvim_buf_set_mark(
      bufnr,
      ">",
      display.focus_node.scope["end"].line,
      display.focus_node.scope["end"].character,
      {}
    )
    comment.locked("toggle.linewise")("v")
    vim.api.nvim_set_current_win(display.mid.winid)
    display.state.leaving_window_for_action = false
  end

  return {
    callback = callback,
    description = "Comment",
  }
end

local function swap_nodes(for_buf, nodeA, nodeB)
  -- nodeA
  --   ^
  --   |
  --   v
  -- nodeB

  fix_end_character_position(for_buf, nodeA.scope)
  fix_end_character_position(for_buf, nodeB.scope)

  if nodeA.scope["end"].line >= nodeB.scope["start"].line and nodeA.parent == nodeB.parent then
    vim.notify("Cannot swap!", vim.log.levels.ERROR)
    return
  end

  local nodeA_text =
    vim.api.nvim_buf_get_lines(for_buf, nodeA.scope["start"].line - 1, nodeA.scope["end"].line - 1 + 1, false)
  local mid_text =
    vim.api.nvim_buf_get_lines(for_buf, nodeA.scope["end"].line - 1 + 1, nodeB.scope["start"].line - 1, false)
  local nodeB_text =
    vim.api.nvim_buf_get_lines(for_buf, nodeB.scope["start"].line - 1, nodeB.scope["end"].line - 1 + 1, false)

  local start_line = nodeA.scope["start"].line - 1
  local nodeA_line_cnt = nodeA.scope["end"].line + 1 - nodeA.scope["start"].line
  local mid_line_cnt = nodeB.scope["start"].line - nodeA.scope["end"].line - 1
  local nodeB_line_cnt = nodeB.scope["end"].line + 1 - nodeB.scope["start"].line

  -- Swap pointers
  nodeA.next = nodeB.next
  nodeB.next = nodeA

  nodeB.prev = nodeA.prev
  nodeA.prev = nodeB

  -- Swap index
  local nodeB_index = nodeB.index
  nodeB.index = nodeA.index
  nodeA.index = nodeB_index

  -- Swap in parent's children array
  local parent = nodeA.parent
  parent.children[nodeA.index] = nodeA
  parent.children[nodeB.index] = nodeB

  -- Adjust line numbers
  nodeA.scope["start"].line = nodeA.scope["start"].line + nodeB_line_cnt + mid_line_cnt
  nodeA.scope["end"].line = nodeA.scope["end"].line + nodeB_line_cnt + mid_line_cnt
  nodeA.name_range["start"].line = nodeA.name_range["start"].line + nodeB_line_cnt + mid_line_cnt
  nodeA.name_range["end"].line = nodeA.name_range["end"].line + nodeB_line_cnt + mid_line_cnt

  nodeB.scope["start"].line = nodeB.scope["start"].line - nodeA_line_cnt - mid_line_cnt
  nodeB.scope["end"].line = nodeB.scope["end"].line - nodeA_line_cnt - mid_line_cnt
  nodeB.name_range["start"].line = nodeB.name_range["start"].line - nodeA_line_cnt - mid_line_cnt
  nodeB.name_range["end"].line = nodeB.name_range["end"].line - nodeA_line_cnt - mid_line_cnt

  -- Set lines
  vim.api.nvim_buf_set_lines(for_buf, start_line, start_line + nodeB_line_cnt, false, nodeB_text)
  vim.api.nvim_buf_set_lines(
    for_buf,
    start_line + nodeB_line_cnt,
    start_line + nodeB_line_cnt + mid_line_cnt,
    false,
    mid_text
  )
  vim.api.nvim_buf_set_lines(
    for_buf,
    start_line + nodeB_line_cnt + mid_line_cnt,
    start_line + nodeB_line_cnt + mid_line_cnt + nodeA_line_cnt,
    false,
    nodeA_text
  )
end

--- Move currently focued node down. Copies entire lines and works only in case
--- there are no overlapping lines between current node and next node.
function actions.move_down()
  local callback = function(display)
    if display.focus_node.next == nil then
      return
    end

    local bufnr = require_symbol(display)
    if not bufnr or not is_symbol_node(display.focus_node.next) then
      return
    end

    swap_nodes(bufnr, display.focus_node, display.focus_node.next)

    redraw(display)
  end

  return {
    callback = callback,
    description = "Move code block down",
  }
end

--- Move currently focued node up. Copies entire lines and works only in case
--- there are no overlapping lines between current node and previous node.
function actions.move_up()
  local callback = function(display)
    if display.focus_node.prev == nil then
      return
    end

    local bufnr = require_symbol(display)
    if not bufnr or not is_symbol_node(display.focus_node.prev) then
      return
    end

    swap_nodes(bufnr, display.focus_node.prev, display.focus_node)

    redraw(display)
  end

  return {
    callback = callback,
    description = "Move code block up",
  }
end

--- Opens vertical split with currently selected node.
--- Will not remember top line like |winsaveview()| does.
--- NOTE: Direction of split is controlled by 'splitright'
function actions.vsplit()
  local callback = function(display)
    select_node(display, "vsplit")
    vim.api.nvim_command("normal! zv")
  end

  return {
    callback = callback,
    description = "Open selected node in a vertical split",
  }
end

--- Acts akin to vsplit, but splits horizontally.
--- NOTE: Direction of split is controlled by 'splitbelow'
function actions.hsplit()
  local callback = function(display)
    select_node(display, "split")
    vim.api.nvim_command("normal! zv")
  end

  return {
    callback = callback,
    description = "Open selected node in a horizontal split",
  }
end

--- Open Fuzzy finder with telescope to search sibling nodes on current level.
--- Can be customized during setup by passing opts table, all configuration
--- passed to telescope.nvim's default option can be passed here.
---@param opts any -- telescope config
function actions.telescope(opts)
  local callback = function(display)
    require("nvim-navbuddy.picker.telescope").find(opts, display)
  end

  return {
    callback = callback,
    description = "Fuzzy search current level with telescope",
  }
end

--- Open Fuzzy finder with your prefered to search sibling nodes on current level.
--- Can be customized during setup by passing opts table, all configuration
--- passed to your picker's default option can be passed here.
---@param opts any -- telescope or snacks config
function actions.fuzzy_find(opts)
  ---@param display Navbuddy.display
  local callback = function(display)
    if utils.check_integration("telescope", display.config) then
      require("nvim-navbuddy.picker.telescope").find(opts, display)
    else
      require("nvim-navbuddy.picker.snacks").find(opts, display)
    end
  end

  return {
    callback = callback,
    description = "Fuzzy search current level with fuzzy picker",
  }
end

--- Open mappings help window
function actions.help()
  local callback = function(display)
    display:close()

    local max_keybinding_len = 0
    for k, _ in pairs(display.config.mappings) do
      max_keybinding_len = math.max(#k, max_keybinding_len)
    end

    local lines = {}
    for k, v in pairs(display.config.mappings) do
      local text = "  " .. k .. string.rep(" ", max_keybinding_len - #k) .. " | " .. v.description
      table.insert(lines, text)
    end
    table.sort(lines)

    local width = math.min(math.max(50, max_keybinding_len + 40), math.floor(vim.o.columns * 0.8))
    local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))
    table.insert(lines, 1, " Navbuddy Mappings" .. string.rep(" ", math.max(1, width - 36)) .. "press 'q' to exit ")
    table.insert(lines, 2, string.rep("-", width))

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false

    local winid = vim.api.nvim_open_win(bufnr, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      border = "single",
      style = "minimal",
    })

    vim.wo[winid].winhighlight = "Normal:NavbuddyNormalFloat,FloatBorder:NavbuddyFloatBorder"

    local function quit_help()
      if vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, true)
      end
      require("nvim-navbuddy.display").new(display)
    end

    vim.keymap.set("n", "q", quit_help, { buffer = bufnr, nowait = true })
    vim.keymap.set("n", "<esc>", quit_help, { buffer = bufnr, nowait = true })

    local help_ns = vim.api.nvim_create_namespace("nvim-navbuddy-help")
    vim.hl.range(bufnr, help_ns, "NavbuddyFunction", { 0, 0 }, { 0, -1 })
    for i = 2, #lines do
      vim.hl.range(bufnr, help_ns, "NavbuddyKey", { i - 1, 0 }, { i - 1, max_keybinding_len + 3 })
    end
  end

  return {
    callback = callback,
    description = "Show mappings",
  }
end

return actions
