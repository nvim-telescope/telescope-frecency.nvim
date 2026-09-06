local DatabaseV2 = require "frecency.v2.database"

---@class FrecencyDatabase
---@field protected _file_lock FrecencyFileLock
---@field protected io_lock vim.async.Semaphore serialises load and save
---@field protected start_task? vim.async.Task set by start(), awaited by file_lock()
---@field protected tbl FrecencyTable
---@field enqueue fun(self, mode: "load"|"save"): nil
---@field file_lock async fun(self): FrecencyFileLock
---@field filename async fun(self): string
---@field get_entries async fun(self, workspaces?: string[], epoch?: integer): FrecencyDatabaseEntry[]
---@field has_entry async fun(self): boolean
---@field insert_files async fun(self, paths: string[]): nil
---@field load async fun(self): nil
---@field new fun(): FrecencyDatabase
---@field query_sorter fun(order: string, direction: "asc"|"desc"): FrecencyDatabaseEntryCmp
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

local M = {}

---@return FrecencyDatabase
function M.create()
  return DatabaseV2.new()
end

return M
