local async = require "plenary.async" --[[@as PlenaryAsync]]
local log = require "frecency.log"

---@class FrecencyFileLock
---@field base string
---@field config FrecencyFileLockConfig
---@field filename string
local FileLock = {}

---@class FrecencyFileLockConfig
---@field retry integer default: 5
---@field interval integer default: 500

---@param path string
---@param opts FrecencyFileLockConfig?
---@return FrecencyFileLock
FileLock.new = function(path, opts)
  local config = vim.tbl_extend("force", { retry = 5, interval = 500 }, opts or {})
  local self = setmetatable({ config = config }, { __index = FileLock })
  self.filename = path .. ".lock"
  return self
end

---@async
---@return string? err
function FileLock:get()
  log.debug "file_lock get() start"
  local count = 0
  local err, fd
  while true do
    count = count + 1
    err, fd = async.uv.fs_open(self.filename, "wx", tonumber("600", 8))
    if not err then
      break
    end
    async.util.sleep(self.config.interval)
    if count == self.config.retry then
      log.debug "file_lock get() failed: retry count reached"
      return ("failed to get lock in %d times"):format(count)
    end
    log.debug(("file_lock get() retry: %d"):format(count))
  end
  err = async.uv.fs_close(fd)
  if err then
    log.debug("file_lock get() failed: " .. err)
    return err
  end
  log.debug "file_lock get() finish"
end

---@async
---@return string? err
function FileLock:release()
  log.debug "file_lock release() start"
  local err = async.uv.fs_stat(self.filename)
  if err then
    log.debug "file_lock release() not found"
    return "lock not found"
  end
  err = async.uv.fs_unlink(self.filename)
  if not err then
    return err
  end
  log.debug "file_lock release() finish"
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
