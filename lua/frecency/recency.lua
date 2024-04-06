local config = require "frecency.config"

---@class FrecencyRecency
---@field private modifier table<integer, { age: integer, value: integer }>
local Recency = {}

---@return FrecencyRecency
Recency.new = function()
  return setmetatable({
    modifier = config.recency_values,
  }, { __index = Recency })
end

---@param count integer
---@param ages number[]
---@return number
function Recency:calculate(count, ages)
  local score = 0
  for _, age in ipairs(ages) do
    for _, rank in ipairs(self.modifier) do
      if age <= rank.age then
        score = score + rank.value
        goto continue
      end
    end
    ::continue::
  end
  return count * score / config.max_timestamps
end

return Recency
