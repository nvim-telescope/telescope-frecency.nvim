local Table = require "frecency.database.table"
local FileLock = require "frecency.file_lock"
local config = require "frecency.config"
local fs = require "frecency.fs"
local watcher = require "frecency.watcher"
local log = require "frecency.log"
local async = require "plenary.async" --[[@as FrecencyPlenaryAsync]]
local Path = require "plenary.path" --[[@as FrecencyPlenaryPath]]

---@class FrecencyDatabaseEntry
---@field ages number[]
---@field count integer
---@field path string
---@field score number
---@field timestamps integer[]

---@class FrecencyDatabase
---@field tx FrecencyPlenaryAsyncControlChannelTx
---@field private file_lock FrecencyFileLock
---@field private filename string
---@field private tbl FrecencyDatabaseTable
---@field private version "v1"
local Database = {}

---@return FrecencyDatabase
Database.new = function()
  local version = "v1"
  local self = setmetatable({
    tbl = Table.new(version),
    version = version,
  }, { __index = Database })
  self.filename = (function()
    -- NOTE: for backward compatibility
    -- If the user does not set db_root specifically, search DB in
    -- $XDG_DATA_HOME/nvim in addition to $XDG_STATE_HOME/nvim (default value).
    local file = "file_frecency.bin"
    local db = Path.new(config.db_root, file)
    if not config.ext_config.db_root and not db:exists() then
      local old_location = Path.new(vim.fn.stdpath "data", file)
      if old_location:exists() then
        return old_location.filename
      end
    end
    return db.filename
  end)()
  self.file_lock = FileLock.new(self.filename)
  local rx
  self.tx, rx = async.control.channel.mpsc()
  self.tx.send "load"
  watcher.watch(self.filename, function()
    self.tx.send "load"
  end)
  async.void(function()
    while true do
      local mode = rx.recv()
      log.debug("DB coroutine start:", mode)
      if mode == "load" then
        self:load()
      elseif mode == "save" then
        self:save()
      else
        log.error("unknown mode: " .. mode)
      end
      log.debug("DB coroutine end:", mode)
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
  self.tx.send "save"
end

---@async
---@return string[]
function Database:unlinked_entries()
  return vim.tbl_flatten(async.util.join(vim.tbl_map(function(path)
    return function()
      local err, realpath = async.uv.fs_realpath(path)
      if err or not realpath or realpath ~= path or fs.is_ignored(realpath) then
        return path
      end
    end
  end, vim.tbl_keys(self.tbl.records))))
end

---@param paths string[]
function Database:remove_files(paths)
  for _, file in ipairs(paths) do
    self.tbl.records[file] = nil
  end
  self.tx.send "save"
end

---@param path string
---@param epoch? integer
function Database:update(path, epoch)
  local record = self.tbl.records[path] or { count = 0, timestamps = {} }
  record.count = record.count + 1
  local now = epoch or os.time()
  table.insert(record.timestamps, now)
  if #record.timestamps > config.max_timestamps then
    local new_table = {}
    for i = #record.timestamps - config.max_timestamps + 1, #record.timestamps do
      table.insert(new_table, record.timestamps[i])
    end
    record.timestamps = new_table
  end
  self.tbl.records[path] = record
  self.tx.send "save"
end

---@param workspace? string
---@param epoch? integer
---@return FrecencyDatabaseEntry[]
function Database:get_entries(workspace, epoch)
  local now = epoch or os.time()
  local items = {}
  for path, record in pairs(self.tbl.records) do
    if fs.starts_with(path, workspace) then
      table.insert(items, {
        path = path,
        count = record.count,
        ages = vim.tbl_map(function(v)
          return (now - v) / 60
        end, record.timestamps),
        timestamps = record.timestamps,
      })
    end
  end
  return items
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
  self.tx.send "save"
  return true
end

return Database
