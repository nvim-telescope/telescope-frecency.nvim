local config = require "frecency.config"

---@class FrecencyRecency
---@field private modifier table<integer, { age: integer, value: integer }>
local Recency = {}

---@return FrecencyRecency
Recency.new = function()
  return setmetatable({
    modifier = {
      { age = 240, value = 100 }, -- past 4 hours
      { age = 1440, value = 80 }, -- past day
      { age = 4320, value = 60 }, -- past 3 days
      { age = 10080, value = 40 }, -- past week
      { age = 43200, value = 20 }, -- past month
      { age = 129600, value = 10 }, -- past 90 days
    },
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
