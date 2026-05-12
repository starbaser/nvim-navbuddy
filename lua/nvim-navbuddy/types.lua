---@alias SectionName "left"|"mid"

---@class Integrations
---@field snacks? boolean
---@field telescope? boolean

---@class WindowSectionConfig
---@field width? string|number
---@field buf_options? table<string, any>
---@field win_options? table<string, any>

---@class WindowConfig
---@field height? string|number
---@field scrolloff? number
---@field sections? { left?: WindowSectionConfig, mid?: WindowSectionConfig }

---@class NodeMarkersIcons
---@field leaf? string
---@field leaf_selected? string
---@field branch? string

---@class NodeMarkersConfig
---@field enabled? boolean
---@field icons? NodeMarkersIcons

---@class LspConfig
---@field auto_attach? boolean
---@field preference? string[]

---@class KeyMapping
---@field callback fun(display: table)
---@field description string

---@class SourceBufferConfig
---@field follow_node? boolean
---@field highlight? boolean
---@field reorient? "smart"|"top"|"mid"|"none"
---@field scrolloff? number

---@class Navbuddy.config
---@field window? WindowConfig
---@field node_markers? NodeMarkersConfig
---@field icons? table<number, string>
---@field use_default_mappings? boolean
---@field mappings? table<string, KeyMapping>
---@field lsp? LspConfig
---@field source_buffer? SourceBufferConfig
---@field custom_hl_group? string
---@field integrations? Integrations Which integrations to enable

---@class Navbuddy.openOpts
---@field root? boolean
---@field bufnr? number

---@class RangePosition
---@field character integer
---@field line integer

---@class Range
---@field start RangePosition
---@field end RangePosition

---@class Navbuddy.symbolNode
---@field is_root? boolean
---@field index integer
---@field memory? integer
---@field kind integer
---@field name string
---@field name_range Range
---@field prev? Navbuddy.symbolNode
---@field next? Navbuddy.symbolNode
---@field scope Range
---@field children? Navbuddy.symbolNode[]|nil
---@field parent? Navbuddy.symbolNode|nil

---@class Navbuddy.pane
---@field winid integer
---@field bufnr integer

---@alias Navbuddy.ActionCallback fun(display: Navbuddy.display)
