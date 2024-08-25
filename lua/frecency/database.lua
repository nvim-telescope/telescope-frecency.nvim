local Table = require "frecency.database.table"
local FileLock = require "frecency.file_lock"
local timer = require "frecency.timer"
local config = require "frecency.config"
local fs = require "frecency.fs"
local watcher = require "frecency.watcher"
local log = require "frecency.log"
local lazy_require = require "frecency.lazy_require"
local async = lazy_require "plenary.async" --[[@as FrecencyPlenaryAsync]]
local Path = lazy_require "plenary.path" --[[@as FrecencyPlenaryPath]]

---@class FrecencyDatabaseEntry
---@field ages number[]
---@field count integer
---@field path string
---@field score number
---@field timestamps integer[]

---@alias FrecencyDatabaseVersion "v1"

---@class FrecencyDatabase
---@field private _file_lock FrecencyFileLock
---@field private file_lock_rx async fun(): ...
---@field private file_lock_tx fun(...): nil
---@field private tbl FrecencyDatabaseTable
---@field private version FrecencyDatabaseVersion
---@field private watcher_rx FrecencyPlenaryAsyncControlChannelRx
---@field private watcher_tx FrecencyPlenaryAsyncControlChannelTx
local Database = {}

---@return FrecencyDatabase
Database.new = function()
  local version = "v1"
  local file_lock_tx, file_lock_rx = async.control.channel.oneshot()
  local watcher_tx, watcher_rx = async.control.channel.mpsc()
  return setmetatable({
    file_lock_rx = file_lock_rx,
    file_lock_tx = file_lock_tx,
    tbl = Table.new(version),
    version = version,
    watcher_rx = watcher_rx,
    watcher_tx = watcher_tx,
  }, { __index = Database })
end

---@async
---@return string
function Database:filename()
  local file_v1 = "file_frecency.bin"

  ---@async
  ---@return string
  local function filename_v1()
    -- NOTE: for backward compatibility
    -- If the user does not set db_root specifically, search DB in
    -- $XDG_DATA_HOME/nvim in addition to $XDG_STATE_HOME/nvim (default value).
    local db = Path.new(config.db_root, file_v1).filename
    if not config.ext_config.db_root and not fs.exists(db) then
      local old_location = Path.new(vim.fn.stdpath "data", file_v1).filename
      if fs.exists(old_location) then
        return old_location
      end
    end
    return db
  end

  if self.version == "v1" then
    return filename_v1()
  else
    error(("unknown version: %s"):format(self.version))
  end
end

---@async
---@return nil
function Database:start()
  local target = self:filename()
  self.file_lock_tx(FileLock.new(target))
  self.watcher_tx.send "load"
  watcher.watch(target, function()
    self.watcher_tx.send "load"
  end)
  async.void(function()
    while true do
      local mode = self.watcher_rx.recv()
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
end

---@async
---@return boolean
function Database:has_entry()
  return not vim.tbl_isempty(self.tbl.records)
end

---@async
---@param paths string[]
---@return nil
function Database:insert_files(paths)
  if #paths == 0 then
    return
  end
  for _, path in ipairs(paths) do
    self.tbl.records[path] = { count = 1, timestamps = { 0 } }
  end
  self.watcher_tx.send "save"
end

---@async
---@return string[]
function Database:unlinked_entries()
  -- HACK: async.util.join() does not work with empty table. So when the table
  -- has no entries, return early.
  -- TODO: This is fixed in https://github.com/nvim-lua/plenary.nvim/pull/616
  local paths = vim.tbl_keys(self.tbl.records)
  return #paths == 0 and {}
    or vim.tbl_flatten(async.util.join(vim.tbl_map(function(path)
      return function()
        local err, realpath = async.uv.fs_realpath(path)
        if err or not realpath or realpath ~= path or fs.is_ignored(realpath) then
          return path
        end
      end
    end, paths)))
end

---@async
---@param paths string[]
function Database:remove_files(paths)
  for _, file in ipairs(paths) do
    self.tbl.records[file] = nil
  end
  self.watcher_tx.send "save"
end

---@async
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
  self.watcher_tx.send "save"
end

---@async
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
  timer.track "load() start"
  local err, data = self:file_lock():with(function(target)
    local err, stat = async.uv.fs_stat(target)
    if err then
      return nil
    end
    local fd
    err, fd = async.uv.fs_open(target, "r", tonumber("644", 8))
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
  timer.track "load() finish"
end

---@async
---@return nil
function Database:save()
  timer.track "save() start"
  local err = self:file_lock():with(function(target)
    self:raw_save(self.tbl:raw(), target)
    local err, stat = async.uv.fs_stat(target)
    assert(not err, err)
    watcher.update(stat)
    return nil
  end)
  assert(not err, err)
  timer.track "save() finish"
end

---@async
---@param target string
---@param tbl FrecencyDatabaseRawTable
function Database:raw_save(tbl, target)
  local f = assert(load("return " .. vim.inspect(tbl)))
  local data = string.dump(f)
  local err, fd = async.uv.fs_open(target, "w", tonumber("644", 8))
  assert(not err, err)
  assert(not async.uv.fs_write(fd, data))
  assert(not async.uv.fs_close(fd))
end

---@async
---@param path string
---@return boolean
function Database:remove_entry(path)
  if not self.tbl.records[path] then
    return false
  end
  self.tbl.records[path] = nil
  self.watcher_tx.send "save"
  return true
end

---@private
---@async
---@return FrecencyFileLock
function Database:file_lock()
  if not self._file_lock then
    self._file_lock = self.file_lock_rx()
  end
  return self._file_lock
end

return Database
