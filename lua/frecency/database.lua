---@diagnostic disable: missing-return, unused-local
---@class FrecencyDatabaseConfig
---@field root string

---@class FrecencyDatabaseGetFilesOptions
---@field path string?
---@field workspace string?

---@class FrecencyDatabase
---@field config FrecencyDatabaseConfig
---@field filename string
---@field has_entry fun(): boolean
---@field new fun(fs: FrecencyFS, config: FrecencyDatabaseConfig): FrecencyDatabase
---@field protected fs FrecencyFS
local Database = {}

---@param paths string[]
---@return nil
function Database:insert_files(paths) end

---@return integer[]|string[]
function Database:unlinked_entries() end

---@param files integer[]|string[]
---@return nil
function Database:remove_files(files) end

---@param path string
---@param max_count integer
---@param datetime string?
---@return nil
function Database:update(path, max_count, datetime) end

---@async
---@class FrecencyDatabaseEntry
---@field ages number[]
---@field count integer
---@field path string
---@field score number

---@param workspace string?
---@param datetime string?
---@return FrecencyDatabaseEntry[]
function Database:get_entries(workspace, datetime) end
