local log = require "frecency.log"
local timer = require "frecency.timer"
local wait = require "frecency.wait"
local lazy_require = require "frecency.lazy_require"
local async = lazy_require "plenary.async" --[[@as FrecencyPlenaryAsync]]

---@class FrecencyTableRecordV1
---@field count integer
---@field timestamps integer[]

---@class FrecencyTableDataV1
---@field records table<string, FrecencyTableRecordV1>
---@field version string

---@class FrecencyTable
---@field version string
---@field private data table raw data from database file
---@field private is_ready boolean

---@class FrecencyTableV1: FrecencyTable
---@field private data FrecencyTableDataV1 raw data from database file
local TableV1 = {}

---@return FrecencyTableV1
TableV1.new = function()
  return setmetatable({ is_ready = false, version = "v1", data = {} }, { __index = TableV1 })
end

---@async
---@return table<string, FrecencyTableRecordV1>
function TableV1:records()
  local is_async = not not coroutine.running()
  if is_async then
    self:wait_ready()
  else
    log.debug "need wait() for wait_ready()"
    wait(function()
      self:wait_ready()
    end)
  end
  return self:get_records()
end

---@protected
---@return table<string, FrecencyTableRecordV1>
function TableV1:get_records()
  return self.data.records
end

---@return FrecencyTableDataV1
function TableV1:raw()
  return { version = self.version, records = self:records() }
end

---@param raw_table? FrecencyTableDataV1
---@return nil
function TableV1:set(raw_table)
  local tbl = raw_table or self:default_table()
  if self.version ~= tbl.version then
    error "Invalid version"
  end
  self.is_ready = true
  self.data = tbl
end

---@return FrecencyTableDataV1
function TableV1:default_table()
  return { version = self.version, records = {} }
end

---@return FrecencyTableRecordV1
function TableV1:default_record() -- luacheck: no self
  return { count = 0, timestamps = {} }
end

---This is for internal or testing use only.
---@async
---@return nil
function TableV1:wait_ready()
  timer.track "wait_ready() start"
  local t = 0.2
  while not rawget(self, "is_ready") do
    async.util.sleep(t)
    t = t * 2
  end
  timer.track "wait_ready() finish"
end

---@param key string
---@return FrecencyTableRecordV1
function TableV1:get_record(key)
  return self.data.records[key]
end

---@param key string
---@param record? FrecencyTableRecordV1
---@return nil
function TableV1:set_record(key, record)
  self.data.records[key] = record or self:default_record()
end

---@param key string
---@return nil
function TableV1:remove_record(key)
  self.data.records[key] = nil
end

return TableV1
