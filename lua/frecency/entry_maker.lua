local WebDevicons = require "frecency.web_devicons"
local config = require "frecency.config"
local Path = require "plenary.path" --[[@as FrecencyPlenaryPath]]
local entry_display = require "telescope.pickers.entry_display" --[[@as FrecencyTelescopeEntryDisplay]]
local utils = require "telescope.utils" --[[@as FrecencyTelescopeUtils]]

---@class FrecencyEntryMaker
---@field fs FrecencyFS
---@field loaded table<string,boolean>
---@field web_devicons WebDevicons
local EntryMaker = {}

---@param fs FrecencyFS
---@return FrecencyEntryMaker
EntryMaker.new = function(fs)
  local self = setmetatable({ fs = fs, web_devicons = WebDevicons.new() }, { __index = EntryMaker })
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
---@field fuzzy_score? number
---@field display fun(entry: FrecencyEntry): string, table

---@class FrecencyFile
---@field count integer
---@field id integer
---@field path string
---@field score integer calculated from count and age

---@alias FrecencyEntryMakerInstance fun(file: FrecencyFile): FrecencyEntry

---@param filepath_formatter FrecencyFilepathFormatter
---@param workspace? string
---@param workspace_tag? string
---@return FrecencyEntryMakerInstance
function EntryMaker:create(filepath_formatter, workspace, workspace_tag)
  -- NOTE: entry_display.create calls non API-fast functions. We cannot call
  -- in entry_maker because it will be called in a Lua loop.
  local displayer = entry_display.create {
    separator = "",
    hl_chars = { [Path.path.sep] = "TelescopePathSeparator" },
    items = self:width_items(workspace, workspace_tag),
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
---@param workspace? string
---@param workspace_tag? string
---@return table[]
function EntryMaker:width_items(workspace, workspace_tag)
  local width_items = {}
  if config.show_scores then
    table.insert(width_items, { width = 5 }) -- recency score
    if config.matcher == "fuzzy" then
      table.insert(width_items, { width = 5 }) -- index
      table.insert(width_items, { width = 6 }) -- fuzzy score
    end
  end
  if self.web_devicons.is_enabled then
    table.insert(width_items, { width = 2 })
  end
  if config.show_filter_column and workspace and workspace_tag then
    table.insert(width_items, { width = self:calculate_filter_column_width(workspace, workspace_tag) })
  end
  -- TODO: This is a stopgap measure to detect placeholders.
  table.insert(width_items, {})
  table.insert(width_items, {})
  table.insert(width_items, {})
  return width_items
end

---@private
---@param entry FrecencyEntry
---@param workspace? string
---@param workspace_tag? string
---@param formatter fun(filename: string): string, FrecencyTelescopePathStyle[]
---@return table[]
function EntryMaker:items(entry, workspace, workspace_tag, formatter)
  local items = {}
  if config.show_scores then
    table.insert(items, { entry.score, "TelescopeFrecencyScores" })
    if config.matcher == "fuzzy" then
      table.insert(items, { entry.index, "TelescopeFrecencyScores" })
      local score = (not entry.fuzzy_score or entry.fuzzy_score == 0) and "0"
        or ("%.3f"):format(entry.fuzzy_score):sub(0, 5)
      table.insert(items, { score, "TelescopeFrecencyScores" })
    end
  end
  if self.web_devicons.is_enabled then
    table.insert(items, { self.web_devicons:get_icon(entry.name, entry.name:match "%a+$", { default = true }) })
  end
  if config.show_filter_column and workspace and workspace_tag then
    local filtered = self:should_show_tail(workspace_tag) and utils.path_tail(workspace) .. Path.path.sep
      or self.fs:relative_from_home(workspace) .. Path.path.sep
    table.insert(items, { filtered, "Directory" })
  end
  local formatted_name, path_style = formatter(entry.name)
  -- NOTE: this means it is formatted with the option: filename_first
  if path_style and type(path_style) == "table" and #path_style > 0 then
    local index = path_style[1][1]
    local filename = formatted_name:sub(1, index[1])
    local parent_path = formatted_name:sub(index[1] + 2, index[2])
    local hl = path_style[1][2]

    table.insert(items, { filename .. " ", self.loaded[entry.name] and "TelescopeBufferLoaded" or "" })
    table.insert(items, { parent_path, hl })
  else
    table.insert(items, { formatted_name, self.loaded[entry.name] and "TelescopeBufferLoaded" or "" })
  end
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
  local show_filter_column = config.show_filter_column
  local filters = type(show_filter_column) == "table" and show_filter_column or { "LSP", "CWD" }
  return vim.tbl_contains(filters, workspace_tag)
end

return EntryMaker
