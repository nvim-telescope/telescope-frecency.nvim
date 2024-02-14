local Work = require "frecency.work"
local wait = require "frececy.wait"
local watcher = require "frecency.watcher"
local worker = require "frecency.database.async.worker"
local Path = require "plenary.path" --[[@as PlenaryPath]]
local async = require "plenary.async" --[[@as PlenaryAsync]]

---@class FrecencyAsyncDatabase: FrecencyDatabase
---@field work FrecencyWork
---@field ready boolean
local Async = {}

---@param fs FrecencyFS
---@param config FrecencyDatabaseConfig
---@return FrecencyDatabase
Async.new = function(fs, config)
  local self = setmetatable({
    config = config,
    fs = fs,
    ready = false,
    table = { version = "v1", records = {} },
    version = "v1",
  }, {
    __index = function(self, key)
      if key == "table" then
        if not self.ready then
          wait(function()
            return self.ready
          end)
        end
        return self[key]
      elseif self[key] then
        return self[key]
      else
        return Async[key]
      end
    end,
  })
  self.filename = Path.new(self.config.root, "file_frecency.bin").filename
  self.work = Work.new(worker)
  local tx, rx = async.control.channel.counter()
  watcher.watch(self.filename, tx)
  async.void(function()
    while true do
      rx.last()
      local err, result = self.work:run { command = "load", filename = self.filename, version = self.version }
      if not err then
        self.table = result --[[@as FrecencyDatabaseTable]]
        local stat
        err, stat = async.uv.fs_stat(self.filename)
        if not err then
          watcher.update(stat)
        end
      end
    end
  end)()
  async.void(function()
    local err, result = self.work:run { command = "load", filename = self.filename, version = self.version }
    if not err then
      self.table = result --[[@as FrecencyDatabaseTable]]
      self.ready = true
      local stat
      err, stat = async.uv.fs_stat(self.filename)
      if not err then
        watcher.update(stat)
      end
    end
  end)()
  return self
end

---@private
---@return nil
function Async:wait_ready()
  if not self.ready then
    wait(function()
      return self.ready
    end)
  end
end

---@return boolean
function Async:has_entry()
  self:wait_ready()
  return not vim.tbl_isempty(self.table.records)
end

---@param paths string[]
---@return nil
function Async:insert_files(paths)
  self:wait_ready()
  if #paths == 0 then
    return
  end
  for _, path in ipairs(paths) do
    self.table.records[path] = { count = 1, timestamps = { 0 } }
  end
  self.work:run_async { command = "save", filename = self.filename, table = self.table }
end

---@return string[]
function Async:unlink_entries()
  self:wait_ready()
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
  self:wait_ready()
  for _, file in ipairs(paths) do
    self.table.records[file] = nil
  end
  self.work:run_async { command = "save", filename = self.filename, table = self.table }
end

---@param path string
---@param max_count integer
---@param datetime string?
---@return nil
function Async:update(path, max_count, datetime)
  self:wait_ready()
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
  self.work:run_async { command = "save", filename = self.filename, table = self.table }
end

---@param workspace string?
---@param datetime string?
---@return FrecencyDatabaseEntry[]
function Async:get_entries(workspace, datetime)
  self:wait_ready()
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
  self:wait_ready()
  if not self.table.records[path] then
    return false
  end
  self.table.records[path] = nil
  self.work:run_async { command = "save", filename = self.filename, table = self.table }
  return true
end

return Async
