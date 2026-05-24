--- *nvim-navbuddy* *navbuddy*
---
--- A simple popup display that provides breadcrumbs like navigation feature but
--- in keyboard centric manner inspired by ranger file manager.

---@text TABLE OF CONTENTS
---
---@toc
---@tag navbuddy-table-of-contents
---@text

---@text REQUIREMENTS
---
--- - nvim-lspconfig: `https://github.com/neovim/nvim-lspconfig`
--- - nvim-navic: `https://github.com/SmiteshP/nvim-navic`
--- - nui.nvim: `https://github.com/MunifTanjim/nui.nvim`
--- - Neovim: 0.8 or above
---
---@text OPTIONAL REQUIREMENTS
---
--- - Comment.nvim: `https://github.com/numToStr/Comment.nvim`
--- - Fuzzy find: Only one of these is needed.
---     - telescope.nvim: `https://github.com/nvim-telescope/telescope.nvim`
---     - snacks.nvim: `https://github.com/folke/snacks.nvim`
---@tag navbuddy-requirements
---@toc_entry Requirements

---@text INSTALLATION
--- >lua
---   -- lazy.nvim
---   {
---     "neovim/nvim-lspconfig",
---     dependencies = {
---       "hasansujon786/nvim-navbuddy",
---       opts = { lsp = { auto_attach = true } }
---       dependencies = {
---         "SmiteshP/nvim-navic",
---         "MunifTanjim/nui.nvim"
---       }
---     }
---   }
--- <
---@tag navbuddy-installation
---@toc_entry Installation

---@text USAGE
---
--- nvim-navbuddy needs to be attached to lsp servers of the buffer to work. Use the
--- navbuddy.attach function while setting up lsp servers. You can skip this
--- step if you have enabled auto_attach option during setup.
---
--- Example: >lua
---   require("lspconfig").clangd.setup {
---     on_attach = function(client, bufnr)
---       navbuddy.attach(client, bufnr)
---     end
---   }
--- <
--- Then simply use command `Navbuddy` to open the window.
---@tag navbuddy-usage
---@toc_entry Usage

---@text COMMANDS
---
--- Navbuddy does not define any default keybindings for nvim. The example
--- keybindings are:
--- >vim
---   nnoremap zo :Navbuddy<cr>
---   nnoremap zi :Navbuddy root<cr>
--- <
--- root~
--- Open navbuddy with root node, the first node left of current node.
---@tag :Navbuddy navbuddy-commands
---@toc_entry Commands

local navic = require("nvim-navic.lib")
local display = require("nvim-navbuddy.display")
local actions = require("nvim-navbuddy.actions")
local workspace = require("nvim-navbuddy.workspace")

-- stylua: ignore start
---@text DEFAULT CONFIG
---
--- Use |navbuddy.setup| to override any of the default options
---
--- window: table
---   Set options related to the navbuddy strip — "height" (of the bottom
---   strip relative to the editor), "scrolloff", and per-section "width"
---   and option overrides.
---
--- icons: table
---   Icons to show for captured symbols. Default icons assume that you
---   have nerd-fonts.
---
--- use_default_mappings: boolean
---   If set to false, only mappings set by user are set. Else default mappings
---   are used for keys that are not set by user.
---
--- mappings: table
---   Actions to be triggered for specified keybindings. For each keybinding
---   it takes a table of format
---   { callback = <function_to_be_called>, description = "string"}.
---   The callback function takes the "display" object as an argument.
---
--- lsp: table
---   auto_attach: boolean
---     Enable to have Navbuddy automatically attach to every LSP for
---     current buffer. Its disabled by default.
---   preference: table
---     Table ranking lsp_servers. Lower the index, higher the priority of
---     the server. If there are more than one server attached to a
---     buffer, navbuddy will refer to this list to make a decision on
---     which one to use.
---     example: Incase a buffer is attached to clangd and ccls both and
---     the preference list is { "clangd", "pyright" }. Then clangd will
---     be prefered.
---
--- workspace: table
---   enabled: boolean
---     Whether workspace-scope navigation is available. Default true.
---   default_scope: string
---     "auto" | "workspace" | "buffer". Picks the default for :Navbuddy
---     when no explicit subcommand is passed. "auto" tries workspace and
---     falls back to buffer if no LSP exposes a workspace root.
---   max_files: integer
---     Hard cap on the breadth-first file scan. A warning is shown if
---     hit. Default 5000.
---   exclude_dirs: string[]
---     Directory basenames skipped during the scan. Defaults include
---     .git, node_modules, target, build, dist, etc.
---   cache: boolean
---     Reuse a single workspace tree across :Navbuddy invocations.
---     Cached per-file symbol entries are invalidated on BufWritePost
---     of the corresponding file. Default false.
---
--- source_buffer:
---   follow_node: boolean
---     Move the source buffer such that focused node is visible.
---   highlight: boolean
---     Highlight focused node on source buffer
---   reorient: string
---     Reorient buffer after changing nodes. options are "smart", "top",
---     "mid" or "none"
---
--- node_markers: table
---   Indicate whether a node is a leaf or branch node. Default icons assume
---   you have nerd-fonts.
---
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@tag navbuddy-config
---@toc_entry Config
---@type Navbuddy.config
--minidoc_replace_start ---@class Navbuddy.config
--minidoc_replace_end
--minidoc_replace_start {
local config = {
  --minidoc_replace_end
  autohide = false,
  window = {
    height = "50%",          -- Height of the navbuddy strip ("NN%" of &lines, or absolute int).
    scrolloff = nil,         -- scrolloff value inside the navbuddy MID window
    sections = {
      left = {
        width = "20%",       -- Width of LEFT pane ("NN%" of &columns, or absolute int).
        win_options = nil,
        buf_options = nil,
      },
      mid = {
        win_options = {
          -- number = true,-- Uncomment this line if you want see the number
          -- relativenumber = true,
        },
        buf_options = nil,
      },
    },
  },
  icons = {
    [1] = "󰈙 ",  -- File
    [2] = " ",  -- Module
    [3] = "󰌗 ",  -- Namespace
    [4] = " ",  -- Package
    [5] = "󰌗 ",  -- Class
    [6] = "󰆧 ",  -- Method
    [7] = " ",  -- Property
    [8] = " ",  -- Field
    [9] = " ",  -- Constructor
    [10] = "󰕘",  -- Enum
    [11] = "󰕘",  -- Interface
    [12] = "󰊕 ", -- Function
    [13] = "󰆧 ", -- Variable
    [14] = "󰏿 ", -- Constant
    [15] = " ", -- String
    [16] = "󰎠 ", -- Number
    [17] = "◩ ", -- Boolean
    [18] = "󰅪 ", -- Array
    [19] = "󰅩 ", -- Object
    [20] = "󰌋 ", -- Key
    [21] = "󰟢 ", -- Null
    [22] = " ", -- EnumMember
    [23] = "󰌗 ", -- Struct
    [24] = " ", -- Event
    [25] = "󰆕 ", -- Operator
    [26] = "󰊄 ", -- TypeParameter
    [255] = "󰉨 ",-- Macro
    directory = "󰉋 ",
    workspace = "󰉋 ",
  },
  use_default_mappings = true,
  -- Each Integration is auto-detected through plugin presence, however, it can
  -- be disabled by setting to `false`
  integrations = {
    -- Requires you to have `nvim-telescope/telescope.nvim` installed.
    telescope = nil,
    -- Requires you to have `folke/snacks.nvim` installed.
    snacks = nil,
  },
  mappings = {
    ["<esc>"] = actions.close(),        -- Close and cursor to original location
    ["q"] = actions.close(),
    ["H"] = actions.toggle_autohide(),  -- Toggle close on leaving Navbuddy

    ["j"] = actions.next_sibling(),     -- Go down
    ["k"] = actions.previous_sibling(), -- Go up

    ["h"] = actions.parent(),           -- Move to left panel
    ["l"] = actions.children(),         -- Move to right panel
    ["0"] = actions.root(),             -- Move to first panel

    ["v"] = actions.visual_name(),      -- Visual selection of name
    ["V"] = actions.visual_scope(),     -- Visual selection of scope

    ["y"] = actions.yank_name(),        -- Yank the name to system clipboard "+
    ["Y"] = actions.yank_scope(),       -- Yank the scope to system clipboard "+

    ["i"] = actions.insert_name(),      -- Insert at start of name
    ["I"] = actions.insert_scope(),     -- Insert at start of scope

    ["a"] = actions.append_name(),      -- Insert at end of name
    ["A"] = actions.append_scope(),     -- Insert at end of scope

    ["r"] = actions.rename(),           -- Rename currently focused symbol

    ["d"] = actions.delete(),           -- Delete scope

    ["f"] = actions.fold_create(),      -- Create fold of current scope
    ["F"] = actions.fold_delete(),      -- Delete fold of current scope

    ["c"] = actions.comment(),          -- Comment out current scope

    ["<enter>"] = actions.select(),     -- Goto selected symbol
    ["o"] = actions.select(),

    ["J"] = actions.move_down(),        -- Move focused node down
    ["K"] = actions.move_up(),          -- Move focused node up

    ["<C-v>"] = actions.vsplit(),       -- Open selected node in a vertical split
    ["<C-s>"] = actions.hsplit(),       -- Open selected node in a horizontal split

    ["t"] = actions.fuzzy_find(),       -- Fuzzy finder at current level.

    ["g?"] = actions.help(),            -- Show keymap help window
  },
  lsp = {
    auto_attach = false,   -- If set to true, you don't need to manually use attach function
    preference = nil,      -- List of lsp server names in order of preference
  },
  workspace = {
    enabled = true,
    default_scope = "auto",  -- "auto"|"workspace"|"buffer"
    max_files = 5000,
    exclude_dirs = {
      ".git",
      ".hg",
      ".svn",
      "node_modules",
      ".direnv",
      "result",
      "target",
      "build",
      "dist",
      "coverage",
    },
  },
  source_buffer = {
    follow_node = true,    -- Keep the current node in focus on the source buffer
    highlight = true,      -- Highlight the currently focused node
    reorient = "smart",    -- "smart"|"top"|"mid"|"none"
    scrolloff = nil,       -- scrolloff value when navbuddy is open
  },
  node_markers = {
    enabled = true,
    icons = {
      leaf = "  ",
      leaf_selected = " → ",
      branch = " ",
    },
  },
  custom_hl_group = nil,   -- "Visual" or any other hl group to use instead of inverted colors
}
--minidoc_afterlines_end
-- stylua: ignore end

setmetatable(config.icons, {
  __index = function()
    return "? "
  end,
})

---@private
---@type table<number, vim.lsp.Client[]>
local navbuddy_attached_clients = {}

local function supports_document_symbols(client)
  if not client then
    return false
  end

  local is_stopped = client.is_stopped
  if type(is_stopped) == "function" then
    if is_stopped(client) then
      return false
    end
  elseif is_stopped then
    return false
  end

  return client.server_capabilities and client.server_capabilities.documentSymbolProvider
end

local function choose_lsp_menu(clients, make_request)
  vim.ui.select(clients, {
    prompt = "Choose LSP Client:",
    format_item = function(client)
      return client.id .. ":" .. client.name
    end,
  }, function(selected)
    if selected then
      make_request(selected)
    end
  end)
end

local function sort_clients_by_preference(clients)
  if config.lsp.preference == nil then
    return clients, 0
  end

  local preferred = {}
  local by_id = {}
  local preferred_count = 0

  for _, preferred_lsp in ipairs(config.lsp.preference) do
    for _, client in ipairs(clients) do
      if preferred_lsp == client.name and by_id[client.id] == nil then
        table.insert(preferred, client)
        by_id[client.id] = true
        preferred_count = preferred_count + 1
      end
    end
  end

  for _, client in ipairs(clients) do
    if by_id[client.id] == nil then
      table.insert(preferred, client)
    end
  end

  return preferred, preferred_count
end

local function select_lsp_client(clients, make_request)
  clients = vim.tbl_filter(supports_document_symbols, clients or {})
  local preferred_count
  clients, preferred_count = sort_clients_by_preference(clients)

  if #clients == 0 then
    return false
  elseif #clients == 1 or preferred_count > 0 then
    make_request(clients[1])
  else
    choose_lsp_menu(clients, make_request)
  end

  return true
end

local function request_buffer(for_buf, handler, opts)
  local function make_request(client)
    navic.request_symbol(for_buf, function(bufnr, symbols)
      navic.update_data(bufnr, symbols)
      navic.update_context(bufnr)
      local tree = require("nvim-navic.lib").get_tree(bufnr)
      if tree then
        require("nvim-navbuddy.augment").augment(bufnr, tree, vim.bo[bufnr].filetype)
      end
      local context_data = navic.get_context_data(bufnr)

      local curr_node = context_data[#context_data]

      handler(for_buf, curr_node, client.name, opts)
    end, client)
  end

  if not select_lsp_client(navbuddy_attached_clients[for_buf], make_request) then
    vim.notify("No lsp servers attached", vim.log.levels.ERROR)
  end
end

---@private
---@param bufnr number
---@param curr_node Navbuddy.symbolNode
---@param lsp_name string
---@param opts Navbuddy.openOpts
local function handler(bufnr, curr_node, lsp_name, opts)
  if curr_node.is_root then
    if curr_node.children then
      local curr_line = vim.api.nvim_win_get_cursor(0)[1]
      local closest_dist = math.abs(curr_line - curr_node.children[1].scope["start"].line)
      local closest_node = curr_node.children[1]

      for _, node in ipairs(curr_node.children) do
        if math.abs(curr_line - node.scope["start"].line) < closest_dist then
          closest_dist = math.abs(curr_line - node.scope["start"].line)
          closest_node = node
        end
      end

      curr_node = closest_node
    else
      return
    end
  end

  while opts.root and curr_node and not curr_node.parent.is_root do
    curr_node = curr_node.parent
  end

  if not curr_node then
    return
  end

  display.new({
    for_buf = bufnr,
    for_win = vim.api.nvim_get_current_win(),
    start_buf = bufnr,
    start_cursor = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win()),
    focus_node = curr_node,
    config = config,
    lsp_name = lsp_name,
  })
end

local function active_clients_for_workspace(bufnr)
  local clients = {}
  local seen = {}

  local function add(client)
    if client and seen[client.id] == nil and supports_document_symbols(client) then
      seen[client.id] = true
      table.insert(clients, client)
    end
  end

  for _, client in ipairs(navbuddy_attached_clients[bufnr] or {}) do
    add(client)
  end

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    add(client)
  end

  return clients
end

local function first_child(root)
  if root.children and root.children[1] then
    return root.children[1]
  end
  return nil
end

local function apply_root_opt(node, opts)
  while opts.root and node and node.parent and not node.parent.is_root do
    node = node.parent
  end
  return node
end

local function open_workspace(bufnr, opts, fallback)
  if config.workspace.enabled == false then
    fallback()
    return
  end

  local function make_request(client)
    local session = workspace.get_or_create(client, bufnr, config)
    local root = session.root or session:build()
    local file_node = session:file_node_for_buf(bufnr)
    local source_win = vim.api.nvim_get_current_win()
    local start_cursor = vim.api.nvim_win_get_cursor(source_win)

    local function open_with_focus(focus_node)
      focus_node = apply_root_opt(focus_node, opts)
      if not focus_node then
        vim.notify("Navbuddy workspace is empty", vim.log.levels.ERROR)
        return
      end

      display.new({
        for_buf = bufnr,
        for_win = source_win,
        start_buf = bufnr,
        start_cursor = start_cursor,
        focus_node = focus_node,
        config = config,
        lsp_name = client.name,
        workspace = session,
      })
    end

    if file_node then
      session:load_symbols(file_node, function(loaded_file)
        open_with_focus(session:closest_symbol(loaded_file, start_cursor))
      end)
    else
      open_with_focus(first_child(root))
    end
  end

  if not select_lsp_client(active_clients_for_workspace(bufnr), make_request) then
    fallback()
  end
end

local navbuddy = {}

local function sync_autohide()
  if vim.g.navbuddy_autohide == nil then
    vim.g.navbuddy_autohide = config.autohide
    return
  end

  config.autohide = vim.g.navbuddy_autohide == true
    or vim.g.navbuddy_autohide == 1
    or vim.g.navbuddy_autohide == "true"
    or vim.g.navbuddy_autohide == "1"
end

local function setup_commands()
  local get_complete = function()
    return { "root", "buffer", "workspace" }
  end

  vim.api.nvim_create_user_command("Navbuddy", function(cmd)
    ---@type Navbuddy.openOpts
    local opts = {}
    for _, arg in ipairs(cmd.fargs) do
      if arg == "root" then
        opts.root = true
      elseif arg == "buffer" or arg == "workspace" then
        opts.scope = arg
      end
    end

    navbuddy.open(opts)
  end, { nargs = "*", complete = get_complete, desc = "Navbuddy" })
end

---@text API
---
--- |nvim-navbuddy| provides the following functions for the user.
---@tag navbuddy-api
---@toc_entry API

--- Configure |nvim-navbuddy|'s options. See more |navbuddy-config|
---@param user_config Navbuddy.config
function navbuddy.setup(user_config)
  if user_config ~= nil then
    if user_config.window ~= nil then
      config.window = vim.tbl_deep_extend("keep", user_config.window, config.window)
    end

    if user_config.autohide ~= nil then
      config.autohide = user_config.autohide
    end

    if user_config.node_markers ~= nil then
      config.node_markers = vim.tbl_deep_extend("keep", user_config.node_markers, config.node_markers)
    end

    if user_config.icons ~= nil then
      for k, v in pairs(user_config.icons) do
        if navic.adapt_lsp_str_to_num(k) then
          config.icons[navic.adapt_lsp_str_to_num(k)] = v
        end
      end
    end

    if user_config.use_default_mappings ~= nil then
      config.use_default_mappings = user_config.use_default_mappings
    end

    if user_config.mappings ~= nil then
      if config.use_default_mappings then
        config.mappings = vim.tbl_deep_extend("keep", user_config.mappings, config.mappings)
      else
        config.mappings = user_config.mappings
      end
    end

    if user_config.lsp ~= nil then
      config.lsp = vim.tbl_deep_extend("keep", user_config.lsp, config.lsp)
    end

    if user_config.workspace ~= nil then
      config.workspace = vim.tbl_deep_extend("keep", user_config.workspace, config.workspace)
    end

    if user_config.source_buffer ~= nil then
      config.source_buffer = vim.tbl_deep_extend("keep", user_config.source_buffer, config.source_buffer)
    end

    if user_config.custom_hl_group ~= nil then
      config.custom_hl_group = user_config.custom_hl_group
    end
  end

  sync_autohide()

  if config.lsp.auto_attach == true then
    local navbuddy_augroup = vim.api.nvim_create_augroup("navbuddy", { clear = false })
    vim.api.nvim_clear_autocmds({ group = navbuddy_augroup })
    vim.api.nvim_create_autocmd("LspAttach", {
      callback = function(args)
        local bufnr = args.buf
        if args.data == nil or args.data.client_id == nil then
          return
        end
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if not client or not client.server_capabilities.documentSymbolProvider then
          return
        end
        navbuddy.attach(client, bufnr)
      end,
    })

    --- Attach to already active clients.
    local all_clients = vim.lsp.get_clients()

    local supported_clients = vim.tbl_filter(function(client)
      return client.server_capabilities.documentSymbolProvider
    end, all_clients)

    for _, client in ipairs(supported_clients) do
      for buffer_number, _ in pairs(client.attached_buffers or {}) do
        navbuddy.attach(client, buffer_number)
      end
    end
  end

  setup_commands()
end

--- Opens Navbuddy for the given buffer or options.
---@param opts? number|Navbuddy.openOpts Optional buffer number or options table.
---        If a number, it's treated as a buffer number.
---        If a table, it may include a `bufnr` field.
---        If omitted, the current buffer is used.
function navbuddy.open(opts)
  -- Get bufnr and validate
  local bufnr = type(opts) == "number" and opts
    or type(opts) == "table" and opts.bufnr
    or vim.api.nvim_get_current_buf()
  assert(vim.api.nvim_buf_is_valid(bufnr), "Invalid buffer number")

  opts = type(opts) == "table" and opts or {}
  local scope = opts.scope or config.workspace.default_scope or "auto"

  if scope == "buffer" then
    request_buffer(bufnr, handler, opts)
  else
    open_workspace(bufnr, opts, function()
      if scope == "workspace" then
        vim.notify("No workspace lsp servers attached", vim.log.levels.ERROR)
        return
      end
      request_buffer(bufnr, handler, opts)
    end)
  end
end

---@param client vim.lsp.Client
---@param bufnr number
function navbuddy.attach(client, bufnr)
  if not client.server_capabilities.documentSymbolProvider then
    if not vim.g.navbuddy_silence then
      vim.notify(
        'nvim-navbuddy: Server "' .. client.name .. '" does not support documentSymbols.',
        vim.log.levels.ERROR
      )
    end
    return
  end

  if navbuddy_attached_clients[bufnr] == nil then
    navbuddy_attached_clients[bufnr] = {}
  end

  -- Check if already attached
  for _, c in ipairs(navbuddy_attached_clients[bufnr]) do
    if c.id == client.id then
      return
    end
  end

  -- Check for stopped lsp servers
  for i, c in ipairs(navbuddy_attached_clients[bufnr]) do
    if c.is_stopped then
      table.remove(navbuddy_attached_clients[bufnr], i)
    end
  end

  table.insert(navbuddy_attached_clients[bufnr], client)

  local navbuddy_augroup = vim.api.nvim_create_augroup("navbuddy", { clear = false })
  vim.api.nvim_clear_autocmds({
    buffer = bufnr,
    group = navbuddy_augroup,
  })
  vim.api.nvim_create_autocmd("BufDelete", {
    callback = function()
      navic.clear_buffer_data(bufnr)
      navbuddy_attached_clients[bufnr] = nil
    end,
    group = navbuddy_augroup,
    buffer = bufnr,
  })
  vim.api.nvim_create_autocmd("LspDetach", {
    callback = function()
      if navbuddy_attached_clients[bufnr] ~= nil then
        for i, c in ipairs(navbuddy_attached_clients[bufnr]) do
          if c.id == client.id then
            table.remove(navbuddy_attached_clients[bufnr], i)
            break
          end
        end
        if #navbuddy_attached_clients[bufnr] == 0 then
          navbuddy_attached_clients[bufnr] = nil
        end
      end
    end,
    group = navbuddy_augroup,
    buffer = bufnr,
  })
end

return navbuddy
