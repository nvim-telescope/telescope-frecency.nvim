local TableV1 = require "frecency.v1.table"
local EntryV2 = require "frecency.v2.entry"

---@class FrecencyDatabaseTableV2: FrecencyDatabaseTable
local TableV2 = setmetatable({}, { __index = TableV1 })

---@return FrecencyDatabaseTableV2
TableV2.new = function()
  local self = setmetatable(TableV1.new(), { __index = TableV2 }) --[[@as FrecencyDatabaseTableV2]]
  self.version = "v2"
  self.data = self:default_table()
  return self
end

---@param v1_tbl table
---@return table
function TableV2:from_v1(v1_tbl)
  return vim.iter(v1_tbl.records):fold(self:default_table(), function(tbl, path, v1)
    local v2 = self:default_record()
    v2.num_accesses = v1.count
    v2.last_accessed = v1.timestamps[#v1.timestamps]
    tbl.records[path] = vim.iter(v1.timestamps):fold(v2, function(record, timestamp)
      local entry = EntryV2.new(path, record, timestamp)
      entry:update(timestamp)
      record.score = entry.score
      return record
    end)
    return tbl
  end)
end

---@protected
---@return table
function TableV2:get_records()
  return self.data.records
end

---@return number
function TableV2:reference_time()
  return self.data.reference_time
end

---@return number
function TableV2:half_life()
  return self.data.half_life
end

---@return table
function TableV2:raw()
  return self.data
end

---@return table
function TableV2:default_table()
  return {
    version = self.version,
    reference_time = os.time(),
    half_life = 60 * 60 * 24 * 3, -- 3 days half life
    records = {},
  }
end

---@return table
function TableV2:default_record()
  return {
    half_life = self:half_life(),
    reference_time = self:reference_time(),
    score = 0,
    last_accessed = 0,
    num_accesses = 0,
  }
end

---@param now? integer
---@return number
function TableV2:half_lives_passed(now)
  return ((now or os.time()) - self:reference_time()) / self:half_life()
end

return TableV2
