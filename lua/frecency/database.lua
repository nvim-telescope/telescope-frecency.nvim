---@diagnostic disable: missing-return, unused-local
---@class FrecencyDatabaseConfig
---@field root string

---@class FrecencyDatabaseGetFilesOptions
---@field path string?
---@field workspace string?

---@class FrecencyDatabase
---@field config FrecencyDatabaseConfig
---@field has_entry fun(): boolean
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
---@param count integer
---@param datetime string?
---@return nil
function Database:update(path, count, datetime) end

---@param workspace string?
---@param datetime string?
---@return { path: string, count: integer, ages: number[] }[]
function Database:get_entries(workspace, datetime) end
