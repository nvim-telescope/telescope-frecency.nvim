local FileLock = require "frecency.file_lock"
local TableV2 = require "frecency.v2.table"
local config = require "frecency.config"
local fs = require "frecency.fs"
local log = require "frecency.log"
local os_util = require "frecency.os_util"
local timer = require "frecency.timer"
local watcher = require "frecency.watcher"
local lazy_require = require "frecency.lazy_require"
local async = lazy_require "neoplen.async" --[[@as FrecencyPlenaryAsync]]

-- todo(clason): remove when dropping support for Nvim 0.12
local npcall = vim.npcall or vim.F.npcall

---@class FrecencyDatabaseV2: FrecencyDatabase
---@field protected tbl FrecencyTableV2
local DatabaseV2 = {}

---@return FrecencyDatabaseV2
DatabaseV2.new = function()
  local file_lock_tx, file_lock_rx = async.control.channel.oneshot()
  local watcher_tx, watcher_rx = async.control.channel.mpsc()
  return setmetatable({
    file_lock_rx = file_lock_rx,
    file_lock_tx = file_lock_tx,
    is_started = false,
    tbl = TableV2.new(),
    watcher_rx = watcher_rx,
    watcher_tx = watcher_tx,
  }, { __index = DatabaseV2 })
end

---@async
---@return string
function DatabaseV2:filename()
  local db = os_util.join_path(config.db_root, "file_frecency_v2.bin")
  if not fs.exists(db) then
    local v1 = self:v1_filename()
    if fs.exists(v1) then
      self:migrate_from(db, v1)
    end
  end
  return db
end

-- v1 file path resolution kept for v1 → v2 auto-migration in 2.0.0. The very
-- old fallback to stdpath "data" is preserved for users who upgraded before
-- the db_root default was switched to stdpath "state" (issue #200).
-- TODO: remove together with the migration path in a later 2.x minor release.
---@async
---@return string
function DatabaseV2:v1_filename() -- luacheck: no self
  local file_v1 = "file_frecency.bin"
  local db = os_util.join_path(config.db_root, file_v1)
  if not config.ext_config.db_root and not fs.exists(db) then
    local old_location = os_util.join_path(vim.fn.stdpath "data", file_v1)
    if fs.exists(old_location) then
      return old_location
    end
  end
  return db
end

---@async
---@param v2 string
---@param v1 string
---@return nil
function DatabaseV2:migrate_from(v2, v1)
  log.debug "migration start"
  log.debug("v2:", v2)
  log.debug("v1:", v1)
  local tbl = self:_load(FileLock.new(v1)) --[[@as FrecencyTableDataV1?]]
  if not tbl then
    return
  end
  self.tbl:set(self.tbl:from_v1(tbl))
  self.watcher_tx.send "save"
  log.debug "migration finish"
  vim.schedule(function()
    vim.notify(
      ("[telescope-frecency] migrated v1 database to v2 (%s -> %s).\n"):format(v1, v2)
        .. "Rankings may shift because the score algorithm changed (count x static recency -> exponential decay).\n"
        .. "The v1 file is preserved on disk for rollback. See :help telescope-frecency-database-v2-migration",
      vim.log.levels.WARN
    )
  end)
end

---@async
---@return nil
function DatabaseV2:start()
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
function DatabaseV2:has_entry()
  return not vim.tbl_isempty(self.tbl:records())
end

---@async
---@param paths string[]
---@return nil
function DatabaseV2:insert_files(paths)
  if #paths == 0 then
    return
  end
  for _, path in ipairs(paths) do
    self.tbl:set_record(path, self.tbl:default_record())
  end
  self.watcher_tx.send "save"
end

---@async
---@return string[]
function DatabaseV2:unlinked_entries()
  local threads = vim
    .iter(self.tbl:records())
    :map(function(path, _)
      return function()
        local err, realpath = async.uv.fs_realpath(path)
        if err or not realpath or realpath ~= path then
          return path
        end
      end
    end)
    :totable()
  return vim.iter(async.util.join(threads)):flatten():totable()
end

---@async
---@param paths string[]
function DatabaseV2:remove_files(paths)
  for _, file in ipairs(paths) do
    self.tbl:remove_record(file)
  end
  self.watcher_tx.send "save"
end

---@async
---@param path string
---@param epoch? integer
function DatabaseV2:update(path, epoch)
  local now = epoch or os.time()
  local entry = self.tbl:entry(path, now)
  entry:update(now)
  self.tbl:set_record(path, entry:record())
  self.watcher_tx.send "save"
end

---@async
---@param workspaces? string[]
---@param epoch? integer
---@return FrecencyDatabaseEntry[]
function DatabaseV2:get_entries(workspaces, epoch)
  local now = epoch or os.time()
  return vim
    .iter(self.tbl:records())
    :filter(function(path, _)
      return not workspaces
        or vim.iter(workspaces):any(function(workspace)
          return fs.starts_with(path, workspace)
        end)
    end)
    :map(function(path, _)
      return self.tbl:entry(path, now)
    end)
    :totable()
end

---@async
---@return nil
function DatabaseV2:load()
  timer.track "load() start"
  log.debug "load v2 start"
  local tbl = self:_load(self:file_lock(), true)
  self.tbl:set(tbl)
  if self.tbl:half_lives_passed() > 5.0 then
    log.debug "half_life recalculation start"
    self.tbl:reset_reference_time()
    log.debug "half_life recalculation finish"
    self.watcher_tx.send "save"
  end
  timer.track "load() finish"
  log.debug "load v2 finish"
end

---@async
---@protected
---@param file_lock FrecencyFileLock
---@param update_watcher? boolean
---@return table?
function DatabaseV2:_load(file_lock, update_watcher) -- luacheck: no self
  local err, data = file_lock:with(function(target)
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
    if update_watcher then
      watcher.update(stat)
    end
    return data
  end)
  assert(not err, err)
  local f = npcall(loadstring, data or "")
  return f and npcall(f)
end

---@async
---@return nil
function DatabaseV2:save()
  timer.track "save() start"
  self:_save(self:file_lock(), true)
  timer.track "save() finish"
end

---@async
---@protected
---@param fl FrecencyFileLock
---@param update_watcher? boolean
---@return nil
function DatabaseV2:_save(fl, update_watcher)
  local err = fl:with(function(target)
    local f = assert(load("return " .. vim.inspect(self.tbl:raw())))
    local data = string.dump(f)
    local err, fd = async.uv.fs_open(target, "w", tonumber("644", 8))
    assert(not err, err)
    assert(not async.uv.fs_write(fd, data))
    assert(not async.uv.fs_close(fd))
    local stat
    err, stat = async.uv.fs_stat(target)
    assert(not err, err)
    if update_watcher then
      watcher.update(stat)
    end
    return nil
  end)
  assert(not err, err)
end

---@async
---@param path string
---@return boolean
function DatabaseV2:remove_entry(path)
  if not self.tbl:records()[path] then
    return false
  end
  self.tbl:remove_record(path)
  self.watcher_tx.send "save"
  return true
end

---@protected
---@async
---@return FrecencyFileLock
function DatabaseV2:file_lock()
  if not self._file_lock then
    self._file_lock = self.file_lock_rx()
  end
  return self._file_lock
end

---@param order string
---@param direction "asc"|"desc"
---@return FrecencyDatabaseEntryCmp
function DatabaseV2.query_sorter(order, direction)
  local is_asc = direction == "asc"
  if order == "count" then
    -- "count" remaps to v2 num_accesses (kept for query() API compatibility).
    if is_asc then
      return function(a, b)
        return a.num_accesses < b.num_accesses or (a.num_accesses == b.num_accesses and a.path < b.path)
      end
    end
    return function(a, b)
      return a.num_accesses > b.num_accesses or (a.num_accesses == b.num_accesses and a.path < b.path)
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
  end
  -- "timestamps" remaps to v2 last_accessed (kept for query() API compatibility).
  if is_asc then
    return function(a, b)
      return a.last_accessed < b.last_accessed or (a.last_accessed == b.last_accessed and a.path < b.path)
    end
  end
  return function(a, b)
    return a.last_accessed > b.last_accessed or (a.last_accessed == b.last_accessed and a.path < b.path)
  end
end

return DatabaseV2
