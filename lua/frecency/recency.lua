local config = require "frecency.config"

---@class FrecencyRecency
local M = {}

---@param count integer
---@param ages number[]
---@return number
function M.calculate(count, ages)
  local score = vim.iter(ages):fold(0, function(a, age)
    local matched = vim.iter(config.recency_values):find(function(rank)
      return age <= rank.age
    end)
    return a + (matched and matched.value or 0)
  end)
  return count * score / config.max_timestamps
end

return M
