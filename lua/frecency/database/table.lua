local log = require "frecency.log"
local timer = require "frecency.timer"
local wait = require "frecency.wait"
local lazy_require = require "frecency.lazy_require"
local async = lazy_require "plenary.async" --[[@as FrecencyPlenaryAsync]]

---@class FrecencyDatabaseRecordValue
---@field count integer
---@field timestamps integer[]

---@class FrecencyDatabaseRawTable
---@field version string
---@field records table<string,FrecencyDatabaseRecordValue>

---@class FrecencyDatabaseTable: FrecencyDatabaseRawTable
---@field private is_ready boolean
local Table = {}

---@param version string
---@return FrecencyDatabaseTable
Table.new = function(version)
  return setmetatable({ is_ready = false, version = version }, { __index = Table.__index })
end

---@async
---@param key string
function Table:__index(key)
  if key == "records" and not rawget(self, "is_ready") then
    local is_async = not not coroutine.running()
    if is_async then
      Table.wait_ready(self)
    else
      log.debug "need wait() for wait_ready()"
      wait(function()
        Table.wait_ready(self)
      end)
    end
  end
  return vim.F.if_nil(rawget(self, key), Table[key])
end

function Table:raw()
  return { version = self.version, records = self.records }
end

---@param raw_table? FrecencyDatabaseRawTable
---@return nil
function Table:set(raw_table)
  local tbl = raw_table or { version = self.version, records = {} }
  if self.version ~= tbl.version then
    error "Invalid version"
  end
  self.is_ready = true
  self.records = tbl.records
end

---This is for internal or testing use only.
---@async
---@return nil
function Table:wait_ready()
  timer.track "wait_ready() start"
  local t = 0.2
  while not rawget(self, "is_ready") do
    async.util.sleep(t)
    t = t * 2
  end
  timer.track "wait_ready() finish"
end

return Table
