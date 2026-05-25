---@text ACTIONS
---
--- |nvim-navbuddy| provides the following actions for the user.
---@tag navbuddy-actions
---@toc_entry Actions

local utils = require("nvim-navbuddy.utils")
local actions = {}

local is_symbol_node = utils.is_symbol_node
local is_container_node = utils.is_container_node
local clamp_cursor = utils.clamp_cursor

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

local MAX_DEFINITION_SCAN_LINES = 5

local function client_for(display, bufnr, capability)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  local fallback

  for _, client in ipairs(clients) do
    local capabilities = client.server_capabilities or {}
    if not capability or capabilities[capability] then
      fallback = fallback or client
      if client.name == display.lsp_name then
        return client
      end
    end
  end

  return fallback
end

local function add_definition_position(positions, seen, line, character)
  if line < 1 or character < 0 then
    return
  end

  local key = line .. ":" .. character
  if seen[key] then
    return
  end

  seen[key] = true
  table.insert(positions, {
    line = line - 1,
    character = character,
  })
end

local function candidate_definition_positions(bufnr, node)
  local positions = {}
  local seen = {}

  if node.name_range and node.name_range.start then
    add_definition_position(positions, seen, node.name_range.start.line, node.name_range.start.character)
  end

  if not node.scope or not node.scope.start or not node.scope["end"] then
    return positions
  end

  local start_line = node.scope.start.line
  local end_line = node.scope["end"].line
  if end_line < start_line or end_line - start_line + 1 > MAX_DEFINITION_SCAN_LINES then
    return positions
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  for i, line in ipairs(lines) do
    local line_nr = start_line + i - 1
    local start_col = line_nr == start_line and node.scope.start.character or 0
    local end_col = line_nr == end_line and node.scope["end"].character or #line
    local segment = line:sub(start_col + 1, end_col)
    local index = 1

    while index <= #segment do
      local quote_start, quote_end = segment:find("['\"]", index)
      if not quote_start then
        break
      end

      local quote = segment:sub(quote_start, quote_start)
      local literal_end = segment:find(quote, quote_end + 1, true)
      if not literal_end then
        break
      end

      if literal_end > quote_end + 1 then
        add_definition_position(positions, seen, line_nr, start_col + quote_end)
      end
      index = literal_end + 1
    end
  end

  return positions
end

local function definition_file_node(display, node, result)
  if not display.workspace or not result then
    return nil
  end

  local locations = result
  if result.uri or result.targetUri then
    locations = { result }
  end

  for _, location in ipairs(locations) do
    local uri = location.targetUri or location.uri
    local file_node = uri and display.workspace:file_node_for_uri(uri)
    if not file_node and uri then
      file_node = display.workspace:external_file_node_for_uri(uri)
    end
    if file_node and file_node.filename ~= node.filename then
      return file_node
    end
  end

  return nil
end

local function resolve_node_definition_target(display, node, done)
  local bufnr = display:ensure_node_buffer(node)
  if not bufnr then
    done(nil)
    return
  end

  local client = client_for(display, bufnr, "definitionProvider")
  if not client then
    done(nil)
    return
  end

  local positions = candidate_definition_positions(bufnr, node)
  local index = 0

  local function request_next()
    if display.state.closed then
      done(nil)
      return
    end

    index = index + 1
    local position = positions[index]
    if not position then
      done(nil)
      return
    end

    client:request("textDocument/definition", {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) },
      position = position,
    }, function(err, result)
      vim.schedule(function()
        if err then
          request_next()
          return
        end

        local file_node = definition_file_node(display, node, result)
        if file_node then
          done(file_node)
          return
        end

        request_next()
      end)
    end, bufnr)
  end

  request_next()
end

local function finish_definition_target_scan(parent)
  parent._definition_targets_scanning = false
  parent._definition_targets_loaded = true

  local callbacks = parent._definition_target_callbacks or {}
  parent._definition_target_callbacks = nil
  for _, callback in ipairs(callbacks) do
    callback()
  end
end

local function try_follow_definition_target(display, done)
  local node = display.focus_node
  local parent = node.parent
  if not display.workspace or not is_symbol_node(node) or not parent or not parent.children then
    return false
  end

  local function follow_if_available()
    if display.state.closed or display.focus_node ~= node then
      return
    end

    local file_node = node._definition_file_node
    if not file_node then
      done(false)
      return
    end

    display:push_module_trail(node, file_node)
    display.focus_node = file_node
    done(true)
  end

  if parent._definition_targets_loaded then
    if node._definition_file_node then
      follow_if_available()
      return true
    end
    return false
  end

  parent._definition_target_callbacks = parent._definition_target_callbacks or {}
  table.insert(parent._definition_target_callbacks, follow_if_available)
  if parent._definition_targets_scanning then
    return true
  end

  parent._definition_targets_scanning = true

  local scan_nodes = {}
  for _, child in ipairs(parent.children) do
    if is_symbol_node(child) and child.children == nil then
      table.insert(scan_nodes, child)
    end
  end

  local remaining = #scan_nodes
  if remaining == 0 then
    finish_definition_target_scan(parent)
    return true
  end

  for _, child in ipairs(scan_nodes) do
    resolve_node_definition_target(display, child, function(file_node)
      child._definition_file_node = file_node
      remaining = remaining - 1
      if remaining == 0 then
        finish_definition_target_scan(parent)
      end
    end)
  end

  return true
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

function actions.toggle_autohide()
  local callback = function(display)
    display.config.autohide = not display.config.autohide
    vim.g.navbuddy_autohide = display.config.autohide
    vim.notify("Navbuddy autohide " .. (display.config.autohide and "enabled" or "disabled"))
  end

  return {
    callback = callback,
    description = "Toggle autohide",
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
    local origin_node = display:pop_module_trail_target(display.focus_node)
    if origin_node then
      display.focus_node = origin_node
      redraw(display)
      return
    end

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

      local leaf_node = display.focus_node
      if
        try_follow_definition_target(display, function(followed)
          if followed then
            actions.children().callback(display)
          elseif not display.state.closed and display.focus_node == leaf_node then
            actions.select().callback(display)
          end
        end)
      then
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
      if not vim.api.nvim_win_is_valid(display.for_win) then
        vim.notify("Navbuddy: source window closed while in help; not reopening", vim.log.levels.WARN)
        return
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
