local log = require "frecency.log"
local lazy_require = require "frecency.lazy_require"
local async = lazy_require "plenary.async" --[[@as FrecencyPlenaryAsync]]
local uv = vim.loop or vim.uv

---@class FrecencyWatcherMtime
---@field sec integer
---@field nsec integer
local Mtime = {}

---@param mtime FsStatMtime
---@return FrecencyWatcherMtime
Mtime.new = function(mtime)
  return setmetatable({ sec = mtime.sec, nsec = mtime.nsec }, Mtime)
end

---@param other FrecencyWatcherMtime
---@return boolean
function Mtime:__eq(other)
  return self.sec == other.sec and self.nsec == other.nsec
end

---@return string
function Mtime:__tostring()
  return string.format("%d.%d", self.sec, self.nsec)
end

---@class FrecencyWatcher
---@field handler UvFsEventHandle
---@field path string
---@field mtime FrecencyWatcherMtime
local Watcher = {}

---@return FrecencyWatcher
Watcher.new = function()
  return setmetatable({ path = "", mtime = Mtime.new { sec = 0, nsec = 0 } }, { __index = Watcher })
end

---@param path string
---@param cb fun(): nil
function Watcher:watch(path, cb)
  if self.handler then
    self.handler:stop()
  end
  self.handler = assert(uv.new_fs_event()) --[[@as UvFsEventHandle]]
  self.handler:start(path, { recursive = true }, function(err, _, _)
    if err then
      log.debug("failed to watch path: " .. err)
      return
    end
    async.void(function()
      -- NOTE: wait for updating mtime
      async.util.sleep(50)
      local stat
      err, stat = async.uv.fs_stat(path)
      if err then
        log.debug("failed to stat path: " .. err)
        return
      end
      local mtime = Mtime.new(stat.mtime)
      if self.mtime ~= mtime then
        log.debug(("mtime changed: %s -> %s"):format(self.mtime, mtime))
        self.mtime = mtime
        cb()
      end
    end)()
  end)
end

local watcher = Watcher.new()

return {
  ---@param path string
  ---@param cb fun(): nil
  ---@return nil
  watch = function(path, cb)
    log.debug("watch path: " .. path)
    watcher:watch(path, cb)
  end,

  ---@param stat FsStat
  ---@return nil
  update = function(stat)
    local mtime = Mtime.new(stat.mtime)
    log.debug(("update mtime: %s -> %s"):format(watcher.mtime, mtime))
    watcher.mtime = mtime
  end,
}
