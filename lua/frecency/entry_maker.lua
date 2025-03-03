local web_devicons = require "frecency.web_devicons"
local config = require "frecency.config"
local fs = require "frecency.fs"
local Path = require "plenary.path"
local lazy_require = require "frecency.lazy_require"
local entry_display = lazy_require "telescope.pickers.entry_display" --[[@as FrecencyTelescopeEntryDisplay]]
local utils = lazy_require "telescope.utils" --[[@as FrecencyTelescopeUtils]]

---@class FrecencyEntryMaker
---@field loaded table<string,boolean>
local EntryMaker = {}

---@return FrecencyEntryMaker
EntryMaker.new = function()
  return setmetatable({}, { __index = EntryMaker })
end

---@class FrecencyEntry
---@field filename string
---@field index integer
---@field ordinal string
---@field name string
---@field score number
---@field fuzzy_score? number
---@field display fun(entry: FrecencyEntry): string, table

---@alias FrecencyEntryMakerInstance fun(file: table): FrecencyEntry

---@param filepath_formatter FrecencyFilepathFormatter
---@param workspaces? string[]
---@param workspace_tag? string
---@return FrecencyEntryMakerInstance
function EntryMaker:create(filepath_formatter, workspaces, workspace_tag)
  -- NOTE: entry_display.create calls non API-fast functions. We cannot call
  -- in entry_maker because it will be called in a Lua loop.
  local displayer = entry_display.create {
    separator = "",
    hl_chars = { [Path.path.sep] = "TelescopePathSeparator" },
    items = self:width_items(workspaces, workspace_tag),
  }

  -- set loaded buffers for highlight
  self.loaded = vim
    .iter(vim.api.nvim_list_bufs())
    :filter(vim.api.nvim_buf_is_loaded)
    :map(vim.api.nvim_buf_get_name)
    :fold({}, function(a, b)
      a[b] = true
      return a
    end)

  return function(file)
    return {
      filename = file.path,
      ordinal = file.path,
      name = file.path,
      score = file.score,
      ---@param entry FrecencyEntry
      ---@return table
      display = function(entry)
        ---@type string
        local matched
        if workspaces then
          matched = vim.iter(workspaces):find(function(workspace)
            return not not entry.name:find(workspace, 1, true)
          end)
        end
        local items = self:items(entry, matched, workspace_tag, filepath_formatter(matched))
        return displayer(items)
      end,
    }
  end
end

---@private
---@param workspaces? string[]
---@param workspace_tag? string
---@return table[]
function EntryMaker:width_items(workspaces, workspace_tag)
  local width_items = {}
  if config.show_scores then
    table.insert(width_items, { width = 6 }) -- recency score
    if config.matcher == "fuzzy" then
      table.insert(width_items, { width = 5 }) -- index
      table.insert(width_items, { width = 6 }) -- fuzzy score
    end
  end
  if not config.disable_devicons then
    table.insert(width_items, { width = 2 })
  end
  if config.show_filter_column and workspaces and #workspaces > 0 and workspace_tag then
    table.insert(width_items, { width = self:calculate_filter_column_width(workspaces, workspace_tag) })
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
  ---@param score number
  ---@return string
  local function format_score(score)
    local fmt = score % 1 == 0 and "%5d" or "%.3f"
    return fmt:format(score):sub(0, 5)
  end

  local items = {}
  if config.show_scores then
    table.insert(items, { format_score(entry.score), "TelescopeFrecencyScores" })
    if config.matcher == "fuzzy" then
      table.insert(items, { ("%4d"):format(entry.index), "TelescopeFrecencyScores" })
      table.insert(items, { format_score(entry.fuzzy_score or 0), "TelescopeFrecencyScores" })
    end
  end
  if not config.disable_devicons then
    local basename = utils.path_tail(entry.name)
    local icon, icon_highlight = web_devicons.get_icon(basename, utils.file_extension(basename), { default = false })
    if not icon then
      icon, icon_highlight = web_devicons.get_icon(basename, nil, { default = true })
    end
    table.insert(items, { icon, icon_highlight })
  end
  if config.show_filter_column and workspace and workspace_tag then
    local filtered = self:should_show_tail(workspace_tag) and utils.path_tail(workspace) .. Path.path.sep
      or fs.relative_from_home(workspace) .. Path.path.sep
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
---@param workspaces string[]
---@param workspace_tag string
---@return integer
function EntryMaker:calculate_filter_column_width(workspaces, workspace_tag)
  local longest = vim.iter(workspaces):fold("", function(a, b)
    return #a > #b and a or b
  end)
  return self:should_show_tail(workspace_tag) and #(utils.path_tail(longest)) + 1
    or #(fs.relative_from_home(longest)) + 1
end

---@private
---@param workspace_tag string
---@return boolean
function EntryMaker.should_show_tail(_, workspace_tag)
  local show_filter_column = config.show_filter_column
  if show_filter_column == false then
    return false
  end
  local filters = type(show_filter_column) == "table" and show_filter_column or { "LSP", "CWD" }
  return vim.list_contains(filters, workspace_tag)
end

return EntryMaker
