local Table = require "frecency.database.table"
local FileLock = require "frecency.file_lock"
local watcher = require "frecency.watcher"
local log = require "plenary.log"
local async = require "plenary.async" --[[@as PlenaryAsync]]
local Path = require "plenary.path" --[[@as PlenaryPath]]

---@class FrecencyDatabaseConfig
---@field root string

---@class FrecencyDatabaseGetFilesOptions
---@field path string?
---@field workspace string?

---@class FrecencyDatabaseEntry
---@field ages number[]
---@field count integer
---@field path string
---@field score number

---@class FrecencyDatabase
---@field private config FrecencyDatabaseConfig
---@field private file_lock FrecencyFileLock
---@field private filename string
---@field private fs FrecencyFS
---@field private tbl FrecencyDatabaseTable
---@field private version "v1"
local Database = {}

---@param fs FrecencyFS
---@param config FrecencyDatabaseConfig
---@return FrecencyDatabase
Database.new = function(fs, config)
  local version = "v1"
  local self = setmetatable({
    config = config,
    fs = fs,
    tbl = Table.new(version),
    version = version,
  }, { __index = Database })
  self.filename = Path.new(self.config.root, "file_frecency.bin").filename
  self.file_lock = FileLock.new(self.filename)
  local tx, rx = async.control.channel.counter()
  watcher.watch(self.filename, tx)
  async.void(function()
    while true do
      self:load()
      rx.last()
      log.debug "file changed. loading..."
    end
  end)()
  return self
end

---@return boolean
function Database:has_entry()
  return not vim.tbl_isempty(self.tbl.records)
end

---@param paths string[]
---@return nil
function Database:insert_files(paths)
  if #paths == 0 then
    return
  end
  for _, path in ipairs(paths) do
    self.tbl.records[path] = { count = 1, timestamps = { 0 } }
  end
  async.void(function()
    self:save()
  end)()
end

---@return string[]
function Database:unlinked_entries()
  local paths = {}
  for file in pairs(self.tbl.records) do
    if not self.fs:is_valid_path(file) then
      table.insert(paths, file)
    end
  end
  return paths
end

---@param paths string[]
function Database:remove_files(paths)
  for _, file in ipairs(paths) do
    self.tbl.records[file] = nil
  end
  async.void(function()
    self:save()
  end)()
end

---@param path string
---@param max_count integer
---@param datetime string?
function Database:update(path, max_count, datetime)
  local record = self.tbl.records[path] or { count = 0, timestamps = {} }
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
  self.tbl.records[path] = record
  async.void(function()
    self:save()
  end)()
end

---@param workspace string?
---@param datetime string?
---@return FrecencyDatabaseEntry[]
function Database:get_entries(workspace, datetime)
  local now = self:now(datetime)
  local items = {}
  for path, record in pairs(self.tbl.records) do
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

-- TODO: remove this func
-- This is a func for testing
---@private
---@param datetime string?
---@return integer
function Database:now(datetime)
  if not datetime then
    return os.time()
  end
  local tz_fix = datetime:gsub("+(%d%d):(%d%d)$", "+%1%2")
  return require("frecency.tests.util").time_piece(tz_fix)
end

---@async
---@return nil
function Database:load()
  local start = os.clock()
  local err, data = self.file_lock:with(function()
    local err, stat = async.uv.fs_stat(self.filename)
    if err then
      return nil
    end
    local fd
    err, fd = async.uv.fs_open(self.filename, "r", tonumber("644", 8))
    assert(not err, err)
    local data
    err, data = async.uv.fs_read(fd, stat.size)
    assert(not err, err)
    assert(not async.uv.fs_close(fd))
    watcher.update(stat)
    return data
  end)
  assert(not err, err)
  local tbl = vim.F.npcall(loadstring(data or ""))
  self.tbl:set(tbl)
  log.debug(("load() takes %f seconds"):format(os.clock() - start))
end

---@async
---@return nil
function Database:save()
  local start = os.clock()
  local err = self.file_lock:with(function()
    self:raw_save(self.tbl:raw())
    local err, stat = async.uv.fs_stat(self.filename)
    assert(not err, err)
    watcher.update(stat)
    return nil
  end)
  assert(not err, err)
  log.debug(("save() takes %f seconds"):format(os.clock() - start))
end

---@async
---@param tbl FrecencyDatabaseRawTable
function Database:raw_save(tbl)
  local f = assert(load("return " .. vim.inspect(tbl)))
  local data = string.dump(f)
  local err, fd = async.uv.fs_open(self.filename, "w", tonumber("644", 8))
  assert(not err, err)
  assert(not async.uv.fs_write(fd, data))
  assert(not async.uv.fs_close(fd))
end

---@param path string
---@return boolean
function Database:remove_entry(path)
  if not self.tbl.records[path] then
    return false
  end
  self.tbl.records[path] = nil
  async.void(function()
    self:save()
  end)()
  return true
end

return Database
