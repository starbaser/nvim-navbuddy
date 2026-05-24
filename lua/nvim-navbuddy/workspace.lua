local navic = require("nvim-navic.lib")

local M = {}
local Workspace = {}
Workspace.__index = Workspace

local uv = vim.uv or vim.loop
local SymbolKind = vim.lsp.protocol.SymbolKind

local function normalize(path)
  if not path or path == "" then
    return path
  end
  if vim.fs and vim.fs.normalize then
    return (vim.fs.normalize(path):gsub("/$", ""))
  end
  return (vim.fn.fnamemodify(path, ":p"):gsub("/$", ""))
end

local function basename(path)
  local name = path:match("([^/]+)$")
  return name ~= nil and name or path
end

local function join_path(...)
  local parts = { ... }
  local path = table.concat(parts, "/")
  path = path:gsub("/+", "/")
  return path
end

local function is_subpath(path, root)
  path = normalize(path)
  root = normalize(root)
  return path == root or vim.startswith(path, root .. "/")
end

local function split_path(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    table.insert(parts, part)
  end
  return parts
end

local function node_range()
  return {
    start = { line = 1, character = 0 },
    ["end"] = { line = 1, character = 0 },
  }
end

local function make_node(node)
  node.kind = node.kind or SymbolKind.File
  node.name_range = node.name_range or node_range()
  node.scope = node.scope or node_range()
  return node
end

local function link_children(node)
  if not node.children then
    return
  end

  table.sort(node.children, function(a, b)
    if a.node_type ~= b.node_type then
      if a.node_type == "directory" then
        return true
      elseif b.node_type == "directory" then
        return false
      end
    end
    return a.name:lower() < b.name:lower()
  end)

  for i, child in ipairs(node.children) do
    child.index = i
    child.parent = node
    child.prev = node.children[i - 1]
    child.next = node.children[i + 1]
    link_children(child)
  end
end

local function filetype_for_buf(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  return vim.bo[bufnr].filetype
end

local function client_request(client, method, params, handler, bufnr)
  if vim.fn.has("nvim-0.11") == 1 then
    return client:request(method, params, handler, bufnr)
  end
  return client.request(method, params, handler, bufnr)
end

local function set_symbol_metadata(node, file_node)
  node.node_type = "symbol"
  node.bufnr = file_node.bufnr
  node.filename = file_node.filename
  node.uri = file_node.uri

  if not node.children then
    return
  end

  for _, child in ipairs(node.children) do
    set_symbol_metadata(child, file_node)
  end
end

function M.client_roots(client)
  local roots = {}
  local seen = {}

  local function add(path, name)
    path = normalize(path)
    if path and path ~= "" and not seen[path] then
      seen[path] = true
      table.insert(roots, { path = path, name = name or basename(path) })
    end
  end

  for _, folder in ipairs(client.workspace_folders or {}) do
    if folder.uri then
      add(vim.uri_to_fname(folder.uri), folder.name)
    end
  end

  if #roots == 0 and client.root_dir then
    add(client.root_dir)
  end

  return roots
end

function M.client_contains(client, path)
  path = path ~= "" and path or vim.fn.getcwd()
  for _, root in ipairs(M.client_roots(client)) do
    if is_subpath(path, root.path) then
      return true
    end
  end
  return false
end

---@param client vim.lsp.Client
---@param anchor_bufnr number
---@param config Navbuddy.config
function M.new(client, anchor_bufnr, config)
  return setmetatable({
    client = client,
    anchor_bufnr = anchor_bufnr,
    config = config,
    files = {},
    truncated = false,
  }, Workspace)
end

function Workspace:_excluded(name)
  for _, excluded in ipairs(self.config.workspace.exclude_dirs or {}) do
    if name == excluded then
      return true
    end
  end
  return false
end

function Workspace:_scan_dir(root, dir, rel, files)
  local handle = uv.fs_scandir(dir)
  if not handle then
    return true
  end

  while true do
    local name, type_ = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    local abs = join_path(dir, name)
    local child_rel = rel == "" and name or join_path(rel, name)

    if type_ == "directory" then
      if not self:_excluded(name) and not self:_scan_dir(root, abs, child_rel, files) then
        return false
      end
    elseif type_ == "file" then
      table.insert(files, { root = root, path = normalize(abs), rel = child_rel })
      if #files >= self.config.workspace.max_files then
        self.truncated = true
        return false
      end
    end
  end

  return true
end

function Workspace:_insert_file(parent, file)
  local parts = split_path(file.rel)
  local node = parent
  local path = file.root.path

  for i, part in ipairs(parts) do
    local is_file = i == #parts
    node.children = node.children or {}
    node._child_map = node._child_map or {}

    if is_file then
      local file_node = make_node({
        node_type = "file",
        name = part,
        filename = file.path,
        uri = vim.uri_from_fname(file.path),
        parent = node,
        kind = SymbolKind.File,
        symbols_loaded = false,
      })
      table.insert(node.children, file_node)
      self.files[file.path] = file_node
    else
      path = join_path(path, part)
      if not node._child_map[part] then
        node._child_map[part] = make_node({
          node_type = "directory",
          name = part,
          filename = path,
          parent = node,
          children = {},
          kind = SymbolKind.Module,
        })
        table.insert(node.children, node._child_map[part])
      end
      node = node._child_map[part]
    end
  end
end

function Workspace:_clear_child_maps(node)
  node._child_map = nil
  if not node.children then
    return
  end
  for _, child in ipairs(node.children) do
    self:_clear_child_maps(child)
  end
end

function Workspace:build()
  local roots = M.client_roots(self.client)

  local root = make_node({
    is_root = true,
    node_type = "workspace",
    name = "workspace",
    children = {},
    index = 1,
    kind = SymbolKind.Module,
  })

  for _, root_info in ipairs(roots) do
    local parent = root
    if #roots > 1 then
      parent = make_node({
        node_type = "directory",
        name = root_info.name,
        filename = root_info.path,
        parent = root,
        children = {},
        kind = SymbolKind.Module,
      })
      table.insert(root.children, parent)
    end

    local files = {}
    self:_scan_dir(root_info, root_info.path, "", files)
    for _, file in ipairs(files) do
      self:_insert_file(parent, file)
    end
  end

  link_children(root)
  self:_clear_child_maps(root)
  self.root = root

  if self.truncated then
    vim.notify(
      "Navbuddy workspace file scan stopped at " .. tostring(self.config.workspace.max_files) .. " files",
      vim.log.levels.WARN
    )
  end

  return root
end

function Workspace:file_node_for_buf(bufnr)
  local filename = normalize(vim.api.nvim_buf_get_name(bufnr))
  return self.files[filename]
end

function Workspace:ensure_buffer(file_node)
  if file_node.bufnr and vim.api.nvim_buf_is_valid(file_node.bufnr) then
    return file_node.bufnr
  end

  local bufnr = vim.fn.bufadd(file_node.filename)
  pcall(vim.fn.bufload, bufnr)
  file_node.bufnr = bufnr
  return bufnr
end

function Workspace:load_symbols(file_node, callback)
  callback = callback or function() end

  if file_node.node_type ~= "file" then
    callback(file_node)
    return
  end

  if file_node.symbols_loaded then
    callback(file_node)
    return
  end

  file_node._symbol_callbacks = file_node._symbol_callbacks or {}
  table.insert(file_node._symbol_callbacks, callback)
  if file_node.symbols_loading then
    return
  end
  file_node.symbols_loading = true

  local bufnr = self:ensure_buffer(file_node)
  local params = {
    textDocument = {
      uri = file_node.uri,
    },
  }

  client_request(self.client, "textDocument/documentSymbol", params, function(err, symbols)
    vim.schedule(function()
      file_node.symbols_loading = false
      file_node.symbols_loaded = true

      if err then
        vim.notify(
          "Navbuddy failed to load symbols for " .. file_node.name .. ": " .. tostring(err.message or err),
          vim.log.levels.ERROR
        )
      elseif symbols and #symbols > 0 then
        local tree = navic.parse(symbols)
        require("nvim-navbuddy.augment").augment(bufnr, tree, filetype_for_buf(bufnr) or "")
        file_node.children = tree.children

        if file_node.children and #file_node.children > 0 then
          for i, child in ipairs(file_node.children) do
            child.parent = file_node
            child.index = i
            child.prev = file_node.children[i - 1]
            child.next = file_node.children[i + 1]
            set_symbol_metadata(child, file_node)
          end
        else
          file_node.children = nil
        end
      end

      local callbacks = file_node._symbol_callbacks or {}
      file_node._symbol_callbacks = nil
      for _, cb in ipairs(callbacks) do
        cb(file_node)
      end
    end)
  end, bufnr)
end

function Workspace:closest_symbol(file_node, cursor_pos)
  local best = file_node

  local function in_range(node)
    local line = cursor_pos[1]
    local char = cursor_pos[2]
    local range = node.scope
    if not range then
      return false
    end
    if line < range.start.line or line > range["end"].line then
      return false
    end
    if line == range.start.line and char < range.start.character then
      return false
    end
    if line == range["end"].line and char > range["end"].character then
      return false
    end
    return true
  end

  local function visit(node)
    if node.node_type == "symbol" and in_range(node) then
      best = node
    end
    for _, child in ipairs(node.children or {}) do
      visit(child)
    end
  end

  visit(file_node)
  return best
end

return M
