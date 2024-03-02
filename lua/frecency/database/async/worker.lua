---@class FrecencyAsyncDatabaseJobData
---@field command string
---@field filename string
---@field table FrecencyDatabaseTable?
---@field version string

---@param encoded_job string
---@return string encoded_job
---@return string? err
---@return string? encoded_result
return function(encoded_job)
  local job = require("string.buffer").decode(encoded_job)
  print(vim.inspect(job))
  local data = job.data
  print "s1"
  local FileLock = require "frecency.file_lock"
  print "s2"
  local async = require "plenary.async" --[[@as PlenaryAsync]]
  print "s3"
  local wait = require "frecency.wait"
  print "s4"
  -- local log = require "pleanry.log"
  print "s5"
  local file_lock = FileLock.new(data.filename)
  print "p1"
  if data.command == "load" then
    print "p2"
    local result
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
          result = tbl
        end
      end
      -- log.debug(("load() takes %f seconds"):format(os.clock() - start))
    end)
    return encoded_job, nil, require("string.buffer").encode(result)
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
    -- log.debug(("save() takes %f seconds"):format(os.clock() - start))
    return encoded_job
  else
    return encoded_job, ("unknown command: %s"):format(data.command)
  end
end
