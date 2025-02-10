local TableV1 = require "frecency.v1.table"
local EntryV2 = require "frecency.v2.entry"

---@class FrecencyTableRecordV2
---@field last_accessed integer
---@field num_accesses integer
---@field score number

---@class FrecencyTableDataV2
---@field half_life integer
---@field records table<string, FrecencyTableRecordV2>
---@field reference_time integer
---@field version string

---@class FrecencyTableV2: FrecencyTableV1
---@field get_record fun(self: FrecencyTableV2, key: string): FrecencyTableRecordV2
---@field records fun(self: FrecencyTableV2): table<string, FrecencyTableRecordV2>
---@field set fun(self: FrecencyTableV2, tbl: FrecencyTableDataV2): nil
---@field set_record fun(self: FrecencyTableV2, key: string, record: FrecencyTableRecordV2): nil
---@field private data FrecencyTableDataV2
local TableV2 = setmetatable({}, { __index = TableV1 })

---@return FrecencyTableV2
TableV2.new = function()
  local self = setmetatable(TableV1.new(), { __index = TableV2 }) --[[@as FrecencyTableV2]]
  self.version = "v2"
  self.data = self:default_table()
  return self
end

---@param v1_tbl FrecencyTableDataV1
---@return FrecencyTableDataV2
function TableV2:from_v1(v1_tbl)
  ---@param tbl FrecencyTableDataV2
  ---@param path string
  ---@param v1 FrecencyTableRecordV1
  return vim.iter(v1_tbl.records):fold(self:default_table(), function(tbl, path, v1)
    local v2 = self:default_record()
    v2.num_accesses = v1.count
    v2.last_accessed = v1.timestamps[#v1.timestamps]
    ---@param record FrecencyTableRecordV2
    ---@param timestamp integer
    tbl.records[path] = vim.iter(v1.timestamps):fold(v2, function(record, timestamp)
      local entry = EntryV2.new(path, record, self:half_life(), self:reference_time(), timestamp)
      entry:update(timestamp)
      record.score = entry.score
      return record
    end)
    return tbl
  end)
end

---@protected
---@return FrecencyTableRecordV2
function TableV2:get_records()
  return self.data.records
end

---@private
---@param path string
---@param record FrecencyTableRecordV2
---@return nil
function TableV2:set_record(path, record)
  self.data.records[path] = record
end

---@return integer
function TableV2:reference_time()
  return self.data.reference_time
end

---@private
---@param epoch integer
---@return nil
function TableV2:set_reference_time(epoch)
  self.data.reference_time = epoch
end

---@return integer
function TableV2:half_life()
  return self.data.half_life
end

---@return FrecencyTableDataV2
function TableV2:raw()
  return self.data
end

---@return FrecencyTableDataV2
function TableV2:default_table()
  return {
    version = self.version,
    reference_time = os.time(),
    half_life = 60 * 60 * 24 * 3, -- 3 days half life
    records = {},
  }
end

---@return FrecencyTableRecordV2
function TableV2:default_record() -- luacheck: no self
  return {
    score = 0,
    last_accessed = 0,
    num_accesses = 0,
  }
end

---@param path string
---@param epoch? integer
---@return FrecencyDatabaseEntryV2
function TableV2:entry(path, epoch)
  local now = epoch or os.time()
  local record = self:get_records()[path] or self:default_record()
  return EntryV2.new(path, record, self:half_life(), self:reference_time(), now)
end

---@param now? integer
---@return number
function TableV2:half_lives_passed(now)
  return ((now or os.time()) - self:reference_time()) / self:half_life()
end

---@param epoch? integer
---@return nil
function TableV2:reset_reference_time(epoch)
  local now = epoch or os.time()
  local delta = self:reference_time() - now
  self:set_reference_time(now)
  for path, _ in pairs(self:records()) do
    local entry = self:entry(path, now)
    entry:update(now)
    entry.last_accessed = entry.last_accessed + delta
    self:set_record(path, entry:record())
  end
end

return TableV2
