local log = require "frecency.log"
local timer = require "frecency.timer"
local wait = require "frecency.wait"
local lazy_require = require "frecency.lazy_require"
local async = lazy_require "plenary.async" --[[@as FrecencyPlenaryAsync]]

---@class FrecencyDatabaseRawTableV1
---@field version string
---@field records table<string, table>

---@class FrecencyDatabaseTableV1: FrecencyDatabaseRawTableV1
---@field private is_ready boolean
local TableV1 = {}

---@return FrecencyDatabaseTableV1
TableV1.new = function()
  return setmetatable({ is_ready = false, version = "v1" }, { __index = TableV1.__index })
end

---@async
---@param key string
function TableV1:__index(key)
  if key == "records" and not rawget(self, "is_ready") then
    local is_async = not not coroutine.running()
    if is_async then
      TableV1.wait_ready(self)
    else
      log.debug "need wait() for wait_ready()"
      wait(function()
        TableV1.wait_ready(self)
      end)
    end
  end
  return vim.F.if_nil(rawget(self, key), TableV1[key])
end

function TableV1:raw()
  return { version = self.version, records = self.records }
end

---@param raw_table? FrecencyDatabaseRawTableV1
---@return nil
function TableV1:set(raw_table)
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
function TableV1:wait_ready()
  timer.track "wait_ready() start"
  local t = 0.2
  while not rawget(self, "is_ready") do
    async.util.sleep(t)
    t = t * 2
  end
  timer.track "wait_ready() finish"
end

return TableV1
