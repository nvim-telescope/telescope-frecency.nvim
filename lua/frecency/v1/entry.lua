local config = require "frecency.config"

---@class FrecencyDatabaseEntryV1: FrecencyDatabaseEntry
---@field count integer
---@field timestamps integer[]
local EntryV1 = {}

---@class FrecencyDatabaseRawEntryV1
---@field ages integer[]
---@field count integer
---@field timestamps integer[]

---@param path string
---@param record FrecencyDatabaseRawEntryV1
---@param epoch? integer
EntryV1.new = function(path, record, epoch)
  local now = epoch or os.time()
  local ages = vim
    .iter(record.timestamps)
    :map(function(timestamp)
      return (now - timestamp) / 60
    end)
    :totable()
  return setmetatable({
    count = record.count,
    path = path,
    score = record.count * EntryV1.calculate(ages) / config.max_timestamps,
    timestamps = record.timestamps,
  }, { __index = EntryV1 })
end

---@param ages number[]
---@return number score
EntryV1.calculate = function(ages)
  return vim.iter(ages):fold(0, function(a, age)
    local matched = vim.iter(config.recency_values):find(function(rank)
      return age <= rank.age
    end)
    return a + (matched and matched.value or 0)
  end)
end

---@return table
function EntryV1:obj()
  return { path = self.path, count = self.count, timestamps = self.timestamps, score = self.score }
end

return EntryV1
