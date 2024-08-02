---@class FrecencyMigratorV2
---@field v1 string
---@field v2 string
local MigratorV2 = {}

---@param v1 string
---@param v2 string
---@return FrecencyMigratorV2
MigratorV2.new = function(v1, v2)
  return setmetatable({ v1 = v1, v2 = v2 }, { __index = MigratorV2 })
end

---@async
function MigratorV2:migrate()
  --
end

return MigratorV2
