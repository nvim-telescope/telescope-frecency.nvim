local DatabaseV1 = require "frecency.v1.database"
local EntryV2 = require "frecency.v2.entry"
local FileLock = require "frecency.file_lock"
local TableV2 = require "frecency.v2.table"
local config = require "frecency.config"
local fs = require "frecency.fs"
local log = require "frecency.log"
local timer = require "frecency.timer"
local lazy_require = require "frecency.lazy_require"
local Path = lazy_require "plenary.path" --[[@as FrecencyPlenaryPath]]

---@class FrecencyDatabaseV2: FrecencyDatabaseV1
---@field private tbl FrecencyDatabaseTableV2
local DatabaseV2 = setmetatable({}, { __index = DatabaseV1 })

---@return FrecencyDatabaseV2
DatabaseV2.new = function()
  local self = setmetatable(DatabaseV1.new(), { __index = DatabaseV2 }) --[[@as FrecencyDatabaseV2]]
  self.version = "v2"
  self.tbl = TableV2.new()
  return self
end

---@async
---@return string
function DatabaseV2:filename()
  local db = Path.new(config.db_root, "file_frecency_v2.bin").filename
  if not fs.exists(db) then
    local v1 = DatabaseV1.filename(self)
    if fs.exists(v1) then
      self:migrate_from(db, v1)
    end
  end
  return db
end

---@async
---@param db string
---@param v1 string
---@return nil
function DatabaseV2:migrate_from(db, v1)
  log.debug "migration start"
  log.debug("v2: " .. db)
  log.debug("v1: " .. v1)
  local tbl = self:_load(FileLock.new(v1))
  if not tbl then
    return
  end
  self.tbl:set(self.tbl:from_v1(tbl))
  self.watcher_tx.send "save"
  log.debug "migration finish"
end

---@return nil
function DatabaseV2:initialize_record(_) -- luacheck: no self
end

---@async
---@param path string
---@param epoch? integer
function DatabaseV2:update(path, epoch)
  local record = self.tbl:records()[path] or self.tbl:default_record()
  local now = epoch or os.time()
  local entry = EntryV2.new(path, record, now)
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
    :map(function(path, record)
      return EntryV2.new(path, record, now)
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
    timer.track "half_life recalculation: start"
    log.debug "half_life recalculation start"
    local now = os.time()
    for path, record in pairs(self.tbl:records()) do
      local entry = EntryV2.new(path, record, now)
      entry:update(now)
      self.tbl:set_record(path, entry:record())
    end
    timer.track "half_life recalculation: finish"
    log.debug "half_life recalculation finish"
    self.watcher_tx.send "save"
  end
  timer.track "load() finish"
  log.debug "load v2 finish"
end

return DatabaseV2
