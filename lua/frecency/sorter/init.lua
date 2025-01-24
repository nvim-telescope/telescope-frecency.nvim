local config = require "frecency.config"
local Default = require "frecency.sorter.default"
local Opened = require "frecency.sorter.opened"
local SameRepo = require "frecency.sorter.same_repo"

---@class FrecencySorter
---@field new fun(): FrecencySorter
---@field sort fun(self: FrecencySorter, entries: FrecencyDatabaseEntry[]): FrecencyDatabaseEntry[]

return {
  ---@return FrecencySorter
  new = function()
    local Klass = config.preceding == "opened" and Opened or config.preceding == "same_repo" and SameRepo or Default
    return Klass.new()
  end,
}
