local EntryV1 = require "frecency.v1.entry"
local TableV1 = require "frecency.v1.table"
local FileLock = require "frecency.file_lock"
local timer = require "frecency.timer"
local config = require "frecency.config"
local fs = require "frecency.fs"
local watcher = require "frecency.watcher"
local log = require "frecency.log"
local lazy_require = require "frecency.lazy_require"
local async = lazy_require "plenary.async" --[[@as FrecencyPlenaryAsync]]
local Path = lazy_require "plenary.path" --[[@as FrecencyPlenaryPath]]

---@class FrecencyDatabaseV1: FrecencyDatabase
local DatabaseV1 = {}

---@return FrecencyDatabaseV1
DatabaseV1.new = function()
  local version = "v1"
  local file_lock_tx, file_lock_rx = async.control.channel.oneshot()
  local watcher_tx, watcher_rx = async.control.channel.mpsc()
  return setmetatable({
    file_lock_rx = file_lock_rx,
    file_lock_tx = file_lock_tx,
    is_started = false,
    tbl = TableV1.new(version),
    version = version,
    watcher_rx = watcher_rx,
    watcher_tx = watcher_tx,
  }, { __index = DatabaseV1 })
end

---@async
---@return string
function DatabaseV1:filename()
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
function DatabaseV1:start()
  timer.track "Database:start() start"
  if self.is_started then
    return
  end
  self.is_started = true
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
  timer.track "Database:start() finish"
end

---@async
---@return boolean
function DatabaseV1:has_entry()
  return not vim.tbl_isempty(self.tbl.records)
end

---@async
---@param paths string[]
---@return nil
function DatabaseV1:insert_files(paths)
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
function DatabaseV1:unlinked_entries()
  local threads = vim
    .iter(self.tbl.records)
    :map(function(path, _)
      return function()
        local err, realpath = async.uv.fs_realpath(path)
        if err or not realpath or realpath ~= path or fs.is_ignored(realpath) then
          return path
        end
      end
    end)
    :totable()
  return vim.iter(async.util.join(threads)):flatten():totable()
end

---@async
---@param paths string[]
function DatabaseV1:remove_files(paths)
  for _, file in ipairs(paths) do
    self.tbl.records[file] = nil
  end
  self.watcher_tx.send "save"
end

---@async
---@param path string
---@param epoch? integer
function DatabaseV1:update(path, epoch)
  local record = self.tbl.records[path] or { count = 0, timestamps = {} }
  record.count = record.count + 1
  local now = epoch or os.time()
  table.insert(record.timestamps, now)
  if #record.timestamps > config.max_timestamps then
    record.timestamps = vim.iter(record.timestamps):skip(#record.timestamps - config.max_timestamps):totable()
  end
  self.tbl.records[path] = record
  self.watcher_tx.send "save"
end

---@async
---@param workspaces? string[]
---@param epoch? integer
---@return FrecencyDatabaseEntry[]
function DatabaseV1:get_entries(workspaces, epoch)
  local now = epoch or os.time()
  return vim
    .iter(self.tbl.records)
    :filter(function(path, _)
      return not workspaces
        or vim.iter(workspaces):any(function(workspace)
          return fs.starts_with(path, workspace)
        end)
    end)
    :map(function(path, record)
      return EntryV1.new(path, record, now)
    end)
    :totable()
end

---@async
---@return nil
function DatabaseV1:load()
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
function DatabaseV1:save()
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
---@param tbl FrecencyDatabaseRawTableV1
function DatabaseV1:raw_save(tbl, target)
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
function DatabaseV1:remove_entry(path)
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
function DatabaseV1:file_lock()
  if not self._file_lock then
    self._file_lock = self.file_lock_rx()
  end
  return self._file_lock
end

---@param order string
---@param direction "asc"|"desc"
---@return FrecencyDatabaseEntryCmp
function DatabaseV1.query_sorter(order, direction)
  local is_asc = direction == "asc"
  if order == "count" then
    if is_asc then
      return function(a, b)
        return a.count < b.count or (a.count == b.count and a.path < b.path)
      end
    end
    return function(a, b)
      return a.count > b.count or (a.count == b.count and a.path < b.path)
    end
  elseif order == "path" then
    if is_asc then
      return function(a, b)
        return a.path < b.path
      end
    end
    return function(a, b)
      return a.path > b.path
    end
  elseif order == "score" then
    if is_asc then
      return function(a, b)
        return a.score < b.score or (a.score == b.score and a.path < b.path)
      end
    end
    return function(a, b)
      return a.score > b.score or (a.score == b.score and a.path < b.path)
    end
  elseif is_asc then
    return function(a, b)
      local a_timestamp = a.timestamps[1] or 0
      local b_timestamp = b.timestamps[1] or 0
      return a_timestamp < b_timestamp or (a_timestamp == b_timestamp and a.path < b.path)
    end
  end
  return function(a, b)
    local a_timestamp = a.timestamps[1] or 0
    local b_timestamp = b.timestamps[1] or 0
    return a_timestamp > b_timestamp or (a_timestamp == b_timestamp and a.path < b.path)
  end
end

return DatabaseV1
