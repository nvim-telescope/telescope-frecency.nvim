local Work = require "frecency.work"
local wait = require "frecency.wait"
local watcher = require "frecency.watcher"
local Path = require "plenary.path" --[[@as PlenaryPath]]
local async = require "plenary.async" --[[@as PlenaryAsync]]

---@class FrecencyAsyncDatabase: FrecencyDatabase
---@field work FrecencyWork
local Async = {}

---@param fs FrecencyFS
---@param config FrecencyDatabaseConfig
---@return FrecencyDatabase
Async.new = function(fs, config)
  local self = setmetatable({
    config = config,
    fs = fs,
    table = nil, -- NOTE: will be set by another coroutine
    version = "v1",
  }, {
    __index = function(self, key)
      if key == "table" then
        if not rawget(self, "table") then
          vim.wait(2000, function()
            return not not rawget(self, "table")
          end)
        end
        return rawget(self, "table")
      end
      return rawget(self, key) or rawget(Async, key)
    end,
  })
  self.filename = Path.new(self.config.root, "file_frecency.bin").filename
  self.work = Work.new()
  local tx, rx = async.control.channel.counter()
  watcher.watch(self.filename, tx)
  async.void(function()
    while true do
      rx.last()
      ---@type string?, FrecencyDatabaseTable?
      local err, result = self.work:run { command = "load", filename = self.filename, version = self.version }
      if not err then
        assert(not not result, "no error found, but result is nil")
        self.table = result
        local stat
        err, stat = async.uv.fs_stat(self.filename)
        if not err then
          watcher.update(stat)
        end
      end
    end
  end)()
  async.void(function()
    ---@type string?, FrecencyDatabaseTable?
    local err, result = self.work:run { command = "load", filename = self.filename, version = self.version }
    if not err then
      assert(not not result, "no error found, but result is nil")
      self.table = result --[[@as FrecencyDatabaseTable]]
      local stat
      err, stat = async.uv.fs_stat(self.filename)
      if not err then
        watcher.update(stat)
      end
    end
  end)()
  return self
end

---@return boolean
function Async:has_entry()
  return not vim.tbl_isempty(self.table.records)
end

---@param paths string[]
---@return nil
function Async:insert_files(paths)
  if #paths == 0 then
    return
  end
  for _, path in ipairs(paths) do
    self.table.records[path] = { count = 1, timestamps = { 0 } }
  end
  self.work:void { command = "save", filename = self.filename, table = self.table, version = self.version }
end

---@return string[]
function Async:unlink_entries()
  local paths = {}
  for file in pairs(self.table.records) do
    if not self.fs:is_valid_path(file) then
      table.insert(paths, file)
    end
  end
  return paths
end

---@param paths string[]
function Async:remove_files(paths)
  for _, file in ipairs(paths) do
    self.table.records[file] = nil
  end
  self.work:void { command = "save", filename = self.filename, table = self.table, version = self.version }
end

---@param path string
---@param max_count integer
---@param datetime string?
---@return nil
function Async:update(path, max_count, datetime)
  local record = self.table.records[path] or { count = 0, timestamps = {} }
  record.count = record.count + 1
  local now = self:now(datetime)
  table.insert(record.timestamps, now)
  if #record.timestamps > max_count then
    local new_table = {}
    for i = #record.timestamps - max_count + 1, #record.timestamps do
      table.insert(new_table, record.timestamps[i])
    end
    record.timestamps = new_table
  end
  self.table.records[path] = record
  self.work:void { command = "save", filename = self.filename, table = self.table, version = self.version }
end

---@param workspace string?
---@param datetime string?
---@return FrecencyDatabaseEntry[]
function Async:get_entries(workspace, datetime)
  local now = self:now(datetime)
  local items = {}
  for path, record in pairs(self.table.records) do
    if self.fs:starts_with(path, workspace) then
      table.insert(items, {
        path = path,
        count = record.count,
        ages = vim.tbl_map(function(v)
          return (now - v) / 60
        end, record.timestamps),
      })
    end
  end
  return items
end

---@param path string
---@return boolean
function Async:remove_entry(path)
  if not self.table.records[path] then
    return false
  end
  self.table.records[path] = nil
  self.work:void { command = "save", filename = self.filename, table = self.table, version = self.version }
  return true
end

-- TODO: remove this func
-- This is a func for testing
---@private
---@param datetime string?
---@return integer
function Async:now(datetime)
  if not datetime then
    return os.time()
  end
  local epoch
  wait(function()
    local tz_fix = datetime:gsub("+(%d%d):(%d%d)$", "+%1%2")
    epoch = require("frecency.tests.util").time_piece(tz_fix)
  end)
  return epoch
end

return Async
