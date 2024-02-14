---@class FrecencyAsyncDatabaseJobData
---@field command string
---@field filename string
---@field table FrecencyDatabaseTable
---@field version string

---@param data FrecencyAsyncDatabaseJobData
---@return string?
---@return FrecencyDatabaseTable?
return function(data)
  local FileLock = require "frecency.file_lock"
  local async = require "plenary.async" --[[@as PlenaryAsync]]
  local wait = require "frececy.wait"
  local log = require "pleanry.log"
  local file_lock = FileLock.new(data.filename)
  if data.command == "load" then
    local table
    wait(function()
      local start = os.clock()
      local err, content = file_lock:with(function()
        local err, stat = async.uv.fs_stat(data.filename)
        if err then
          return nil
        end
        local fd
        err, fd = async.uv.fs_open(data.filename, "r", tonumber("644", 8))
        assert(not err, err)
        local content
        err, content = async.uv.fs_read(fd, stat.size)
        assert(not err, err)
        assert(not async.uv.fs_close(fd))
        return content
      end)
      if not err then
        local tbl = loadstring(content or "")() --[[@as FrecencyDatabaseTable?]]
        if tbl and tbl.version == data.version then
          table = tbl
        end
      end
      log.debug(("load() takes %f seconds"):format(os.clock() - start))
    end)
    return nil, table
  elseif data.command == "save" then
    local start = os.clock()
    local err = file_lock:with(function()
      local f = assert(load("return " .. vim.inspect(data.table)))
      local encoded = string.dump(f)
      local err, fd = async.uv.fs_open(data.filename, "w", tonumber("644", 8))
      assert(not err, err)
      assert(not async.uv.fs_write(fd, encoded))
      assert(not async.uv.fs_close(fd))
      return nil
    end)
    assert(not err, err)
    log.debug(("save() takes %f seconds"):format(os.clock() - start))
    return
  else
    error(("unknown command: %s"):format(data.command))
  end
end
