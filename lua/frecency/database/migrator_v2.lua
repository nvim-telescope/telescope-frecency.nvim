local Database=require'frecency.database'

---@class FrecencyMigratorV2
---@field v1 FrecencyDatabase
---@field v2 FrecencyDatabase
local MigratorV2 = {}

---@param v1_filename string
---@param v2_filename string
---@return FrecencyMigratorV2
MigratorV2.new = function(v1_filename, v2_filename)
  local v1=Database.new()
  v1:setup_file_lock(v1_filename)
  local v2=Database.new()
  v2:setup_file_lock(v2_filename)
  return setmetatable({ v1 = v1, v2 = v2 }, { __index = MigratorV2 })
end

---@async
function MigratorV2:migrate()
  --
end

return MigratorV2
