local config = require "frecency.config"

---@class FrecencyRecency
local M = {}

---@param count integer
---@param ages number[]
---@return number
function M.calculate(count, ages)
  local score = 0
  for _, age in ipairs(ages) do
    for _, rank in ipairs(config.recency_values) do
      if age <= rank.age then
        score = score + rank.value
        goto continue
      end
    end
    ::continue::
  end
  return count * score / config.max_timestamps
end

return M
