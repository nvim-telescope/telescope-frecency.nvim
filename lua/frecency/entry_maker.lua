local Path = require "plenary.path" --[[@as FrecencyPlenaryPath]]
local entry_display = require "telescope.pickers.entry_display" --[[@as FrecencyTelescopeEntryDisplay]]
local utils = require "telescope.utils" --[[@as FrecencyTelescopeUtils]]

---@class FrecencyEntryMaker
---@field config FrecencyEntryMakerConfig
---@field fs FrecencyFS
---@field loaded table<string,boolean>
---@field web_devicons WebDevicons
local EntryMaker = {}

---@class FrecencyEntryMakerConfig
---@field show_filter_column boolean|string[]
---@field show_scores boolean

---@param fs FrecencyFS
---@param web_devicons WebDevicons
---@param config FrecencyEntryMakerConfig
---@return FrecencyEntryMaker
EntryMaker.new = function(fs, web_devicons, config)
  local self = setmetatable({ config = config, fs = fs, web_devicons = web_devicons }, { __index = EntryMaker })
  local loaded_bufnrs = vim.tbl_filter(function(v)
    return vim.api.nvim_buf_is_loaded(v)
  end, vim.api.nvim_list_bufs())
  self.loaded = {}
  for _, bufnr in ipairs(loaded_bufnrs) do
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname then
      self.loaded[bufname] = true
    end
  end
  return self
end

---@class FrecencyEntry
---@field filename string
---@field index integer
---@field ordinal string
---@field name string
---@field score number
---@field display fun(entry: FrecencyEntry): string, table

---@class FrecencyFile
---@field count integer
---@field id integer
---@field path string
---@field score integer calculated from count and age

---@alias FrecencyEntryMakerInstance fun(file: FrecencyFile): FrecencyEntry

---@param filepath_formatter FrecencyFilepathFormatter
---@param workspace string?
---@param workspace_tag string?
---@return FrecencyEntryMakerInstance
function EntryMaker:create(filepath_formatter, workspace, workspace_tag)
  local displayer = entry_display.create {
    separator = "",
    hl_chars = { [Path.path.sep] = "TelescopePathSeparator" },
    items = self:displayer_items(workspace, workspace_tag),
  }

  return function(file)
    return {
      filename = file.path,
      ordinal = file.path,
      name = file.path,
      score = file.score,
      ---@param entry FrecencyEntry
      ---@return table
      display = function(entry)
        local items = self:items(entry, workspace, workspace_tag, filepath_formatter(workspace))
        return displayer(items)
      end,
    }
  end
end

---@private
---@param workspace string?
---@param workspace_tag string?
---@return table[]
function EntryMaker:displayer_items(workspace, workspace_tag)
  local items = {}
  if self.config.show_scores then
    table.insert(items, { width = 8 })
  end
  if self.web_devicons.is_enabled then
    table.insert(items, { width = 2 })
  end
  if self.config.show_filter_column and workspace and workspace_tag then
    table.insert(items, { width = self:calculate_filter_column_width(workspace, workspace_tag) })
  end
  table.insert(items, { remaining = true })
  return items
end

---@private
---@param entry FrecencyEntry
---@param workspace string?
---@param workspace_tag string?
---@param formatter fun(filename: string): string
---@return table[]
function EntryMaker:items(entry, workspace, workspace_tag, formatter)
  local items = {}
  if self.config.show_scores then
    table.insert(items, { entry.score, "TelescopeFrecencyScores" })
  end
  if self.web_devicons.is_enabled then
    table.insert(items, { self.web_devicons:get_icon(entry.name, entry.name:match "%a+$", { default = true }) })
  end
  if self.config.show_filter_column and workspace and workspace_tag then
    local filtered = self:should_show_tail(workspace_tag) and utils.path_tail(workspace) .. Path.path.sep
      or self.fs:relative_from_home(workspace) .. Path.path.sep
    table.insert(items, { filtered, "Directory" })
  end
  table.insert(items, { formatter(entry.name), self.loaded[entry.name] and "TelescopeBufferLoaded" or "" })
  return items
end

---@private
---@param workspace string
---@param workspace_tag string
---@return integer
function EntryMaker:calculate_filter_column_width(workspace, workspace_tag)
  return self:should_show_tail(workspace_tag) and #(utils.path_tail(workspace)) + 1
    or #(self.fs:relative_from_home(workspace)) + 1
end

---@private
---@param workspace_tag string
---@return boolean
function EntryMaker:should_show_tail(workspace_tag)
  local show_filter_column = self.config.show_filter_column
  local filters = type(show_filter_column) == "table" and show_filter_column or { "LSP", "CWD" }
  return vim.tbl_contains(filters, workspace_tag)
end

return EntryMaker
