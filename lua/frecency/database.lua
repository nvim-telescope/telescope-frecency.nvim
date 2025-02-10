local DatabaseV1 = require "frecency.v1.database"
local DatabaseV2 = require "frecency.v2.database"

---@class FrecencyDatabase
---@field protected _file_lock FrecencyFileLock
---@field protected file_lock_rx async fun(): ...
---@field protected file_lock_tx fun(...): nil
---@field protected is_started boolean
---@field protected tbl FrecencyTable
---@field protected version FrecencyDatabaseVersion
---@field protected watcher_rx FrecencyPlenaryAsyncControlChannelRx
---@field protected watcher_tx FrecencyPlenaryAsyncControlChannelTx
---@field file_lock async fun(self): FrecencyFileLock
---@field filename async fun(self): string
---@field get_entries async fun(self, workspaces?: string[], epoch?: integer): FrecencyDatabaseEntry[]
---@field has_entry async fun(self): boolean
---@field insert_files async fun(self, paths: string[]): nil
---@field load async fun(self): nil
---@field new fun(): FrecencyDatabase
---@field query_sorter fun(order: string, direction: "asc"|"desc"): FrecencyDatabaseEntryCmp
---@field raw_save async fun(self, tbl: table, target: string): nil
---@field remove_entry async fun(self, path: string): boolean
---@field remove_files async fun(self, paths: string[]): nil
---@field save async fun(self): nil
---@field start async fun(self): nil
---@field unlinked_entries async fun(self): string[]
---@field update async fun(self, path: string, epoch?: integer): nil

---@class FrecencyDatabaseEntry
---@field obj fun(self): table
---@field path string
---@field score number

---@alias FrecencyDatabaseEntryCmp fun(a: table, b: table): boolean
---@alias FrecencyDatabaseVersion "v1"|"v2"

local M = {}

---@param version FrecencyDatabaseVersion
---@return FrecencyDatabase
function M.create(version)
  if version == "v1" then
    return DatabaseV1.new()
  elseif version == "v2" then
    return DatabaseV2.new()
  else
    error(("unknown version: %s"):format(version))
  end
end

return M
