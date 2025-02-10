---@class FrecencyDatabaseEntryV2: FrecencyTableRecordV2
---@field half_life integer
---@field path string
---@field reference_time integer
---@field score number
local EntryV2 = {}

---@param path string
---@param record FrecencyTableRecordV2
---@param half_life integer
---@param reference_time integer
---@param epoch? integer
---@return FrecencyDatabaseEntryV2
EntryV2.new = function(path, record, half_life, reference_time, epoch)
  local now = epoch or os.time()
  local self = setmetatable({
    path = path,
    half_life = half_life,
    reference_time = reference_time,
    last_accessed = record.last_accessed,
    num_accesses = record.num_accesses,
    score = record.score,
  }, { __index = EntryV2 })
  self.score = self:get_score(now)
  return self
end

---@class FrecencyDatabaseObjV2: FrecencyTableRecordV2
---@field path string
---@field score number

---@return FrecencyDatabaseObjV2
function EntryV2:obj()
  return {
    path = self.path,
    half_life = self.half_life,
    reference_time = self.reference_time,
    last_accessed = self.last_accessed,
    num_accesses = self.num_accesses,
    score = self.score,
  }
end

---@return FrecencyTableRecordV2
function EntryV2:record()
  return {
    score = self.score,
    last_accessed = self.last_accessed,
    num_accesses = self.num_accesses,
  }
end

---@param now? integer
---@return nil
function EntryV2:update(now)
  local epoch = now or os.time()
  self:set_score(self.score + 1, epoch)
  self.num_accesses = self.num_accesses + 1
  self.last_accessed = epoch - self.reference_time
end

---@param now integer
---@return number
function EntryV2:get_score(now)
  local tmp = math.pow(2, (now - self.reference_time) / self.half_life)
  return tmp == 0 and 0 or self.score / tmp
end

---@param score number
---@param now integer
---@return nil
function EntryV2:set_score(score, now)
  self.score = score * math.pow(2, (now - self.reference_time) / self.half_life)
end

---@param now? integer
function EntryV2:reset_reference_time(now)
  local epoch = now or os.time()
  self:set_score(self.score, epoch)
  local delta = self.reference_time - epoch
  self.reference_time = epoch
  self.last_accessed = self.last_accessed + delta
end

return EntryV2
