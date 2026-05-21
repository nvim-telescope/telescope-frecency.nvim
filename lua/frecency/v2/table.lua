local EntryV2 = require "frecency.v2.entry"
local log = require "frecency.log"
local timer = require "frecency.timer"
local wait = require "frecency.wait"
local lazy_require = require "frecency.lazy_require"
local async = lazy_require "neoplen.async" --[[@as FrecencyPlenaryAsync]]

-- v1 record / data shape kept here because TableV2:from_v1 still consumes
-- them for the v1 → v2 migration in 2.0.0.
-- TODO: remove together with the migration path in a later 2.x minor release.
---@class FrecencyTableRecordV1
---@field count integer
---@field timestamps integer[]

---@class FrecencyTableDataV1
---@field records table<string, FrecencyTableRecordV1>
---@field version string

---@class FrecencyTableRecordV2
---@field last_accessed integer
---@field num_accesses integer
---@field score number

---@class FrecencyTableDataV2
---@field half_life integer
---@field records table<string, FrecencyTableRecordV2>
---@field reference_time integer
---@field version string

---@class FrecencyTable
---@field version string

---@class FrecencyTableV2: FrecencyTable
---@field private data FrecencyTableDataV2
---@field private is_ready boolean
local TableV2 = {}

---@return FrecencyTableV2
TableV2.new = function()
  local self = setmetatable({ is_ready = false, version = "v2", data = {} }, { __index = TableV2 })
  ---@cast self FrecencyTableV2
  self.data = self:default_table()
  return self
end

---@async
---@return table<string, FrecencyTableRecordV2>
function TableV2:records()
  local is_async = not not coroutine.running()
  if is_async then
    self:wait_ready()
  else
    log.debug "need wait() for wait_ready()"
    wait(function()
      self:wait_ready()
    end)
  end
  return self.data.records
end

---@param key string
---@return FrecencyTableRecordV2
function TableV2:get_record(key)
  return self.data.records[key]
end

---@param key string
---@param record FrecencyTableRecordV2
---@return nil
function TableV2:set_record(key, record)
  self.data.records[key] = record
end

---@param key string
---@return nil
function TableV2:remove_record(key)
  self.data.records[key] = nil
end

---@param raw_table? FrecencyTableDataV2
---@return nil
function TableV2:set(raw_table)
  local tbl = raw_table or self:default_table()
  if self.version ~= tbl.version then
    error "Invalid version"
  end
  self.is_ready = true
  self.data = tbl
end

---@return FrecencyTableDataV2
function TableV2:raw()
  return self.data
end

---This is for internal or testing use only.
---@async
---@return nil
function TableV2:wait_ready()
  timer.track "wait_ready() start"
  local t = 0.2
  while not rawget(self, "is_ready") do
    async.util.sleep(t)
    t = t * 2
  end
  timer.track "wait_ready() finish"
end

-- v1 → v2 migration helper. Kept in 2.0.0 for transparent upgrade of existing
-- file_frecency.bin databases. Will be removed together with the v1 read path
-- in a later 2.x minor release.
---@param v1_tbl FrecencyTableDataV1
---@return FrecencyTableDataV2
function TableV2:from_v1(v1_tbl)
  ---@param tbl FrecencyTableDataV2
  ---@param path string
  ---@param v1 FrecencyTableRecordV1
  return vim.iter(v1_tbl.records):fold(self:default_table(), function(tbl, path, v1)
    local v2 = self:default_record()
    v2.num_accesses = v1.count
    ---@param record FrecencyTableRecordV2
    ---@param timestamp integer
    tbl.records[path] = vim.iter(v1.timestamps):fold(v2, function(record, timestamp)
      local entry = EntryV2.new(path, record, self:half_life(), self:reference_time(), timestamp)
      entry:update(timestamp)
      -- entry:update() stores last_accessed as a delta from reference_time.
      -- Mirror it back so the persisted record matches the format new entries
      -- produce, instead of being stuck on the absolute v1 epoch.
      record.score = entry.score
      record.last_accessed = entry.last_accessed
      return record
    end)
    return tbl
  end)
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
  local record = self.data.records[path] or self:default_record()
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
