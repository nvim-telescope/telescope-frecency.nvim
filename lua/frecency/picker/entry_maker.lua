local WebDevicons = require "frecency.web_devicons"
local Path = require "plenary.path" --[[@as PlenaryPath]]
local entry_display = require "telescope.pickers.entry_display" --[[@as TelescopeEntryDisplay]]
local utils = require "telescope.utils" --[[@as TelescopeUtils]]

---@class FrecencyEntryMaker
---@field config FrecencyEntryMakerConfig
---@field loaded table<string,boolean>
local EntryMaker = {}

---@class FrecencyEntryMakerConfig
---@field show_scores boolean
---@field show_filter_column boolean|string[]
---@field os_home string

---@param config FrecencyEntryMakerConfig
---@return FrecencyEntryMaker
EntryMaker.new = function(config)
  local self = setmetatable({ config = config }, { __index = EntryMaker })
  local loaded_bufnrs = vim.tbl_filter(function(v)
    return vim.api.nvim_buf_is_loaded(v)
  end, vim.api.nvim_list_bufs())
  self.loaded = {}
  for _, bufnr in ipairs(loaded_bufnrs) do
    self.loaded[vim.fn.bufname(bufnr)] = true
  end
  return self
end

---@class FrecencyEntry
---@field filename string
---@field ordinal string
---@field name string
---@field score number
---@field display fun(entry: FrecencyEntry): string, table

---@param workspace string?
---@return fun(file: FrecencyFile): FrecencyEntry
function EntryMaker:create(workspace)
  local displayer = entry_display.create {
    separator = "",
    hl_chars = { [Path.path.sep] = "TelescopePathSeparator" },
    items = self:displayer_items(workspace),
  }
  -- TODO: define opts here
  local formatter = self:filepath_formatter({}, workspace)

  return function(file)
    return {
      filename = file.path,
      ordinal = file.path,
      name = file.path,
      score = file.score,
      ---@param entry FrecencyEntry
      ---@return table
      display = function(entry)
        local items = self:items(entry, workspace, formatter)
        return displayer(items)
      end,
    }
  end
end

---@private
---@param workspace string?
---@return table[]
function EntryMaker:displayer_items(workspace)
  local items = {}
  if self.config.show_scores then
    table.insert(items, { width = 8 })
  end
  if WebDevicons.is_enabled() then
    table.insert(items, { width = 2 })
  end
  if self.config.show_filter_column and workspace then
    table.insert(items, { width = self:calculate_filter_column_width(workspace) })
  end
  table.insert(items, { remaining = true })
  return items
end

---@private
---@param entry FrecencyEntry
---@param workspace string?
---@param formatter fun(filename: string): string
---@return table[]
function EntryMaker:items(entry, workspace, formatter)
  local items = {}
  if self.config.show_scores then
    table.insert(items, { entry.score, "TelescopeFrecencyScores" })
  end
  if WebDevicons.is_enabled() then
    table.insert(items, { WebDevicons.get_icon(entry.name, entry.name:match "%a+$", { default = true }) })
  end
  if self.config.show_filter_column and workspace then
    local filtered = self:should_show_tail(workspace) and utils.path_tail(workspace) .. Path.path.sep
      or Path:new(workspace):make_relative(self.config.os_home) .. Path.path.sep
    table.insert(items, { filtered, "Directory" })
  end
  table.insert(items, { formatter(entry.name), self.loaded[entry.name] and "TelescopeBufferLoaded" or "" })
  return items
end

---@private
---@param workspace string
---@return integer
function EntryMaker:calculate_filter_column_width(workspace)
  return self:should_show_tail(workspace) and #(utils.path_tail(workspace)) + 1
    or #(Path:new(workspace):make_relative(self.config.os_home)) + 1
end

---@private
---@param workspace string
---@return boolean
function EntryMaker:should_show_tail(workspace)
  local show_filter_column = self.config.show_filter_column
  local filters = type(show_filter_column) == "table" and show_filter_column or { "LSP", "CWD" }
  return vim.tbl_contains(filters, workspace)
end

---@private
---@param opts TelescopeTransformPathOpts
---@param workspace string?
---@return fun(filename: string): string
function EntryMaker:filepath_formatter(opts, workspace)
  local path_opts = {}
  for k, v in pairs(opts) do
    path_opts[k] = v
  end
  path_opts.cwd = workspace or self.config.os_home

  return function(filename)
    return utils.transform_path(path_opts, filename)
  end
end

return EntryMaker
