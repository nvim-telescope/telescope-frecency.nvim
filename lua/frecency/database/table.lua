local wait = require "frecency.wait"
local log = require "plenary.log"

---@class FrecencyDatabaseRecord
---@field count integer
---@field timestamps integer[]

---@class FrecencyDatabaseRawTable
---@field version string
---@field records table<string,FrecencyDatabaseRecord>

---@class FrecencyDatabaseTable: FrecencyDatabaseRawTable
---@field private is_ready boolean
local Table = {}

---@param version string
---@return FrecencyDatabaseTable
Table.new = function(version)
  return setmetatable({ is_ready = false, version = version }, { __index = Table.__index })
end

function Table:__index(key)
  if key == "records" and not rawget(self, "is_ready") then
    local start = os.clock()
    log.debug "waiting start"
    Table.wait_ready(self)
    log.debug(("waiting until DB become clean takes %f seconds"):format(os.clock() - start))
  end
  log.debug(("is_ready: %s, key: %s, value: %s"):format(rawget(self, "is_ready"), key, rawget(self, key)))
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
---@return nil
function Table:wait_ready()
  vim.wait(2000, function()
    return rawget(self, "is_ready")
  end)
end

return Table
