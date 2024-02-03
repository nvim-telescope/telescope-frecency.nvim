---@class FrecencyDatabaseConfig
---@field root string

---@class FrecencyDatabaseGetFilesOptions
---@field path string?
---@field workspace string?

---@class FrecencyDatabaseEntry
---@field ages number[]
---@field count integer
---@field path string
---@field score number

---@class FrecencyDatabase
---@field config FrecencyDatabaseConfig
---@field file_lock FrecencyFileLock
---@field filename string
---@field fs FrecencyFS
---@field get_entries fun(self: FrecencyDatabase, workspace: string?, datetime: string?): FrecencyDatabaseEntry[]
---@field has_entry fun(self: FrecencyDatabase): boolean
---@field insert_files fun(self: FrecencyDatabase, paths: string[]): nil
---@field new fun(fs: FrecencyFS, config: FrecencyDatabaseConfig): FrecencyDatabase
---@field remove_entry fun(self: FrecencyDatabase, path: string): boolean
---@field remove_files fun(self: FrecencyDatabase, paths: string[]): nil
---@field table FrecencyDatabaseTable
---@field unlinked_entries fun(self: FrecencyDatabase): string[]
---@field update fun(self: FrecencyDatabase, path: string, max_count: integer, datetime: string?): nil
---@field version "v1"

---@class FrecencyDatabaseTable
---@field version string
---@field records table<string,FrecencyDatabaseRecord>

---@class FrecencyDatabaseRecord
---@field count integer
---@field timestamps integer[]
