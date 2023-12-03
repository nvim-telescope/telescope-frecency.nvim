local async = require "plenary.async" --[[@as PlenaryAsync]]
local log = require "plenary.log"

---@class FrecencyFileLock
---@field base string
---@field config FrecencyFileLockConfig
---@field filename string
local FileLock = {}

---@class FrecencyFileLockConfig
---@field retry integer default: 5
---@field unlink_retry integer default: 5
---@field interval integer default: 500

---@param path string
---@param opts FrecencyFileLockConfig?
---@return FrecencyFileLock
FileLock.new = function(path, opts)
  local config = vim.tbl_extend("force", { retry = 5, unlink_retry = 5, interval = 500 }, opts or {})
  local self = setmetatable({ config = config }, { __index = FileLock })
  self.filename = path .. ".lock"
  return self
end

---@async
---@return string? err
function FileLock:get()
  local count = 0
  local unlink_count = 0
  local err, fd
  while true do
    count = count + 1
    err, fd = async.uv.fs_open(self.filename, "wx", tonumber("600", 8))
    if not err then
      break
    end
    async.util.sleep(self.config.interval)
    if count >= self.config.retry then
      log.debug(("file_lock get(): retry count reached. try to delete the lock file: %d"):format(count))
      err = async.uv.fs_unlink(self.filename)
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
  local err = async.uv.fs_stat(self.filename)
  if err then
    log.debug("file_lock release() not found: " .. err)
    return "lock not found"
  end
  err = async.uv.fs_unlink(self.filename)
  if err then
    log.debug("file_lock release() unlink failed: " .. err)
    return err
  end
end

---@async
---@generic T
---@param f fun(): T
---@return string? err
---@return T
function FileLock:with(f)
  local err = self:get()
  if err then
    return err, nil
  end
  local ok, result_or_err = pcall(f)
  err = self:release()
  if err then
    return err, nil
  elseif ok then
    return nil, result_or_err
  end
  return result_or_err, nil
end

return FileLock
