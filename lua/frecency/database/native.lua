local FileLock = require "frecency.file_lock"
local wait = require "frecency.wait"
local log = require "plenary.log"
local async = require "plenary.async" --[[@as PlenaryAsync]]

---@class FrecencyDatabaseNative: FrecencyDatabase
---@field version "v1"
---@field filename string
---@field file_lock FrecencyFileLock
---@field table FrecencyDatabaseNativeTable
local Native = {}

---@class FrecencyDatabaseNativeTable
---@field version string
---@field records table<string,FrecencyDatabaseNativeRecord>

---@class FrecencyDatabaseNativeRecord
---@field count integer
---@field timestamps integer[]

---@param fs FrecencyFS
---@param config FrecencyDatabaseConfig
---@return FrecencyDatabaseNative
Native.new = function(fs, config)
  local version = "v1"
  local self = setmetatable({
    config = config,
    fs = fs,
    table = { version = version, records = {} },
    version = version,
  }, { __index = Native })
  self.filename = self.config.root .. "/file_frecency.bin"
  self.file_lock = FileLock.new(self.filename)
  wait(function()
    self:load()
  end)
  return self
end

---@return boolean
function Native:has_entry()
  return not vim.tbl_isempty(self.table.records)
end

---@param paths string[]
---@return nil
function Native:insert_files(paths)
  if #paths == 0 then
    return
  end
  for _, path in ipairs(paths) do
    self.table.records[path] = { count = 1, timestamps = { 0 } }
  end
  wait(function()
    self:save()
  end)
end

---@return string[]
function Native:unlinked_entries()
  local paths = {}
  for file in pairs(self.table.records) do
    if not self.fs:is_valid_path(file) then
      table.insert(paths, file)
    end
  end
  return paths
end

---@param paths string[]
function Native:remove_files(paths)
  for _, file in ipairs(paths) do
    self.table.records[file] = nil
  end
  wait(function()
    self:save()
  end)
end

---@param path string
---@param max_count integer
---@param datetime string?
function Native:update(path, max_count, datetime)
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
  wait(function()
    self:save()
  end)
end

---@param workspace string?
---@param datetime string?
---@return FrecencyDatabaseEntry[]
function Native:get_entries(workspace, datetime)
  -- TODO: check mtime of DB and reload it
  -- self:load()
  local now = self:now(datetime)
  local items = {}
  for path, record in pairs(self.table.records) do
    if not workspace or path:find(workspace .. "/", 1, true) then
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

---@private
---@param datetime string?
---@return integer
function Native:now(datetime)
  return datetime and vim.fn.strptime("%FT%T%z", datetime) or os.time()
end

---@async
---@return nil
function Native:load()
  local start = os.clock()
  local err, data = self.file_lock:with(function()
    local err, stat = async.uv.fs_stat(self.filename)
    if err then
      return nil
    end
    local fd
    err, fd = async.uv.fs_open(self.filename, "r", tonumber("644", 8))
    assert(not err)
    local data
    err, data = async.uv.fs_read(fd, stat.size)
    assert(not err)
    assert(not async.uv.fs_close(fd))
    return data
  end)
  assert(not err, err)
  local tbl = loadstring(data or "")() --[[@as FrecencyDatabaseNativeTable?]]
  if tbl and tbl.version == self.version then
    self.table = tbl
  end
  log.debug(("load() takes %f seconds"):format(os.clock() - start))
end

---@async
---@return nil
function Native:save()
  local start = os.clock()
  local err = self.file_lock:with(function()
    local f = assert(load("return " .. vim.inspect(self.table)))
    local data = string.dump(f)
    local err, fd = async.uv.fs_open(self.filename, "w", tonumber("644", 8))
    assert(not err)
    assert(not async.uv.fs_write(fd, data))
    assert(not async.uv.fs_close(fd))
    return nil
  end)
  assert(not err, err)
  log.debug(("save() takes %f seconds"):format(os.clock() - start))
end

return Native
