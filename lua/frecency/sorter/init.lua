local config = require "frecency.config"
local Default = require "frecency.sorter.default"
local Opened = require "frecency.sorter.opened"
local SameRepo = require "frecency.sorter.same_repo"

---@class FrecencySorter
---@field new fun(): FrecencySorter
---@field sort fun(self: FrecencySorter, files: FrecencyDatabaseEntry[]): FrecencyDatabaseEntry[]

return config.preceding == "opened" and Opened or config.preceding == "same_repo" and SameRepo or Default
