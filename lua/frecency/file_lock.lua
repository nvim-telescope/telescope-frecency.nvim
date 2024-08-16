local log = require "frecency.log"
local lazy_require = require "frecency.lazy_require"
local Path = lazy_require "plenary.path" --[[@as FrecencyPlenaryPath]]
local async = lazy_require "plenary.async" --[[@as FrecencyPlenaryAsync]]

---@class FrecencyFileLock
---@field base string
---@field config FrecencyFileLockRawConfig
---@field lock string
---@field target string
local FileLock = {}

---@class FrecencyFileLockConfig
---@field retry? integer default: 5
---@field unlink_retry? integer default: 5
---@field interval? integer default: 500

---@class FrecencyFileLockRawConfig
---@field retry integer default: 5
---@field unlink_retry integer default: 5
---@field interval integer default: 500

---@param target string
---@param file_lock_config? FrecencyFileLockConfig
---@return FrecencyFileLock
FileLock.new = function(target, file_lock_config)
  log.debug(("file_lock new(): %s"):format(target))
  local config = vim.tbl_extend("force", { retry = 5, unlink_retry = 5, interval = 500 }, file_lock_config or {})
  return setmetatable({ config = config, lock = target .. ".lock", target = target }, { __index = FileLock })
end

---@async
---@return string? err
function FileLock:get()
  local count = 0
  local unlink_count = 0
  local err, fd
  while true do
    count = count + 1
    local dir = Path.new(self.lock):parent()
    if not dir:exists() then
      -- TODO: make this call be async
      log.debug(("file_lock get(): mkdir parent: %s"):format(dir.filename))
      ---@diagnostic disable-next-line: undefined-field
      dir:mkdir { parents = true }
    end
    err, fd = async.uv.fs_open(self.lock, "wx", tonumber("600", 8))
    if not err then
      break
    end
    async.util.sleep(self.config.interval)
    if count >= self.config.retry then
      log.debug(("file_lock get(): retry count reached. try to delete the lock file: %d"):format(count))
      err = async.uv.fs_unlink(self.lock)
      if err then
        log.debug("file_lock get() failed: " .. err)
        unlink_count = unlink_count + 1
        if unlink_count >= self.config.unlink_retry then
          log.error("file_lock get(): failed to unlink the lock file: " .. err)
          return "failed to get lock"
        end
      end
    end
    log.debug(("file_lock get() retry: %d"):format(count))
  end
  err = async.uv.fs_close(fd)
  if err then
    log.debug("file_lock get() failed: " .. err)
    return err
  end
end

---@async
---@return string? err
function FileLock:release()
  local err = async.uv.fs_stat(self.lock)
  if err then
    log.debug("file_lock release() not found: " .. err)
    return "lock not found"
  end
  err = async.uv.fs_unlink(self.lock)
  if err then
    log.debug("file_lock release() unlink failed: " .. err)
    return err
  end
end

---@async
---@generic T
---@param f fun(target: string): T
---@return string? err
---@return T
function FileLock:with(f)
  local err = self:get()
  if err then
    return err, nil
  end
  local ok, result_or_err = pcall(f, self.target)
  err = self:release()
  if err then
    return err, nil
  elseif ok then
    return nil, result_or_err
  end
  return result_or_err, nil
end

return FileLock
