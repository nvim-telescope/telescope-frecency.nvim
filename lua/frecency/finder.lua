local AsyncFinder = require "frecency.async_finder"
local finders = require "telescope.finders"
local log = require "frecency.log"

---@class FrecencyFinder
---@field private config FrecencyFinderConfig
---@field private entry_maker FrecencyEntryMaker
---@field private fs FrecencyFS
local Finder = {}

---@class FrecencyFinderConfig
---@field chunk_size integer

---@param entry_maker FrecencyEntryMaker
---@param fs FrecencyFS
---@param config FrecencyFinderConfig?
---@return FrecencyFinder
Finder.new = function(entry_maker, fs, config)
  return setmetatable(
    { config = vim.tbl_extend("force", { chunk_size = 1000 }, config or {}), entry_maker = entry_maker, fs = fs },
    { __index = Finder }
  )
end

---@class FrecencyFinderOptions
---@field need_scandir boolean
---@field workspace string?
---@field workspace_tag string?

---@param state FrecencyState
---@param filepath_formatter FrecencyFilepathFormatter
---@param initial_results table
---@param opts FrecencyFinderOptions
---@return table
function Finder:start(state, filepath_formatter, initial_results, opts)
  local entry_maker = self.entry_maker:create(filepath_formatter, opts.workspace, opts.workspace_tag)
  if not opts.need_scandir then
    return finders.new_table {
      results = initial_results,
      entry_maker = entry_maker,
    }
  end
  log.debug { finder = opts }
  return AsyncFinder.new(state, self.fs, opts.workspace, entry_maker, initial_results)
end

return Finder
