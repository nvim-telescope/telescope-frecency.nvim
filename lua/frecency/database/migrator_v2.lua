local Database = require "frecency.database"
local async = require "plenary.async"--[[@as FrecencyPlenaryAsync]]

---@class FrecencyMigratorV2
---@field v1 FrecencyDatabase
---@field v2 FrecencyDatabase
local MigratorV2 = {}

---@param v1_filename string
---@param v2_filename string
---@return FrecencyMigratorV2
MigratorV2.new = function(v1_filename, v2_filename)
  local v1 = Database.new "v1"
  v1:setup_file_lock(v1_filename)
  local v2 = Database.new()
  v2:setup_file_lock(v2_filename)
  return setmetatable({ v1 = v1, v2 = v2 }, { __index = MigratorV2 })
end

---@async
function MigratorV2:migrate()
  self.v1:load()
  ---@param filename string
  ---@param value FrecencyDatabaseRecordValue
  async.util.join(vim.iter(self.v1.tbl.records):map(function(filename, value)
    return function()
      --
    end
  end))
end

---@async
---@param filename string
---@param value FrecencyDatabaseRecordValue
---@return nil
function MigratorV2:update_entry(filename, value)
  local entry = self.v1.tbl.records[filename] or value
  local err, realpath = async.uv.fs_realpath(filename)
  if err or not realpath then
    -- NOTE: this means the path does not exist.
    return
  elseif filename ~= realpath and self.v1.tbl.records[realpath] then
    local original=self.v2.records[realpath] or { count=0,timestamps={}}
  end
  self.v2.tbl.records[realpath] = entry
end

return MigratorV2
