-- Thin facade over |vim.async|.
--
-- Everything this plugin needs from an async runtime goes through here: the
-- pieces `vim.async` does not provide (an unbounded channel, `join()`) live in
-- this file, and tests stub `async.uv.*` through it.
--
-- NOTE: `vim.async` is a lazily loaded field of `vim`, so it is only touched
-- inside function bodies. Requiring this module during startup then costs
-- nothing until the first async call.

---@class FrecencyAsync
local M = {}

---@param f async fun(...): ...
---@param ... any arguments passed to `f`
---@return vim.async.Task
function M.run(f, ...)
  return vim.async.run(f, ...)
end

---@async
---@param ... any see |vim.async.await()|
---@return ...
function M.await(...)
  return vim.async.await(...)
end

---Make an async function out of a callback-style one.
---@param argc integer the position the callback is inserted at
---@param f function
---@return async fun(...): ...
function M.wrap(argc, f)
  return vim.async.wrap(argc, f)
end

---Make a fire-and-forget async function.
---
---The returned function starts a detached task, so a caller inside another
---task neither waits for it nor cancels it on its own completion. Detached
---failures are silent by default, hence `raise_on_error()`.
---@param f async fun(...): ...
---@return fun(...): vim.async.Task
function M.void(f)
  return function(...)
    return vim.async.run(f, ...):detach():raise_on_error()
  end
end

---Yield back to the main loop.
---
---`vim.async` resumes a task in whatever context completed the awaited
---operation, which for libuv calls is a fast event. Call this before touching
---|vim.api| or |vim.fn| to avoid `E5560`.
---@async
---@return nil
function M.scheduler()
  vim.async.await(vim.schedule)
end

---@async
---@param ms integer
---@return nil
function M.sleep(ms)
  vim.async.sleep(ms)
end

---@param permits? integer default: 1
---@return vim.async.Semaphore
function M.semaphore(permits)
  return vim.async.semaphore(permits)
end

---Run an async function from synchronous code and wait for the result.
---@param f async fun(): ...
---@param timeout? integer ms, default: 2000
---@return ...
function M.block_on(f, timeout)
  return vim.async.run(f):wait(timeout or 2000)
end

---Run async functions concurrently and collect their results.
---
---Results keep the order of `fns`; each entry holds the packed return values
---of the corresponding function.
---@async
---@param fns (async fun(): ...)[]
---@param limit? integer max number of functions running at once
---@return table[]
function M.join(fns, limit)
  local semaphore = limit and vim.async.semaphore(limit)
  local tasks = {}
  for i, f in ipairs(fns) do
    tasks[i] = vim.async.run(function()
      if semaphore then
        return semaphore:with(f)
      end
      return f()
    end)
  end
  local results = {}
  for i, task in ipairs(tasks) do
    results[i] = { vim.async.await(task) }
  end
  return results
end

---@class FrecencyAsyncChannelTx
---@field send fun(value?: any): nil

---@class FrecencyAsyncChannelRx
---@field recv async fun(): any?

---@class FrecencyAsyncChannel
M.channel = {}

---Create an unbounded multiple-producer single-consumer channel.
---
---`send()` never suspends and can be called from any context, a fast event
---included. `recv()` suspends the calling task while the channel is empty.
---
---`vim.async` has no public channel: |vim.async.Queue| lives in a private
---module, so this is built on |vim.async.await()| alone. Values are stored by
---index instead of `table.insert()` so that `nil` survives a round trip -- the
---finder sends it to mark the end of a stream.
---@return FrecencyAsyncChannelTx tx
---@return FrecencyAsyncChannelRx rx
function M.channel.mpsc()
  local items = {}
  local first, last = 1, 0
  ---@type (fun()|false)[]
  local waiters = {}

  -- Wake a single waiter. Cancelled ones are left in the list as `false` by
  -- the close handler below, so skip them.
  local function wake()
    while #waiters > 0 do
      local waiter = table.remove(waiters, 1)
      if waiter then
        waiter()
        return
      end
    end
  end

  local tx = {
    ---@param value? any
    ---@return nil
    send = function(value)
      last = last + 1
      items[last] = value
      wake()
    end,
  }

  local rx = {
    ---@async
    ---@return any?
    recv = function()
      -- A wake-up is not a guarantee that a value is still there: another
      -- consumer may have taken it. Re-check instead of assuming.
      while first > last do
        vim.async.await(function(callback)
          waiters[#waiters + 1] = callback
          return {
            close = function(_, on_close)
              for i, waiter in ipairs(waiters) do
                if waiter == callback then
                  waiters[i] = false
                  break
                end
              end
              if on_close then
                on_close()
              end
            end,
          }
        end)
      end
      local value = items[first]
      items[first] = nil
      first = first + 1
      return value
    end,
  }

  return tx, rx
end

---@class FrecencyAsyncUv
M.uv = {}

---@async
---@param path string
---@return string? err
---@return FsStat stat
function M.uv.fs_stat(path)
  local err, stat = vim.async.await(2, vim.uv.fs_stat, path)
  return err, stat
end

---@async
---@param path string
---@param flags string|integer
---@param mode integer
---@return string? err
---@return integer fd
function M.uv.fs_open(path, flags, mode)
  local err, fd = vim.async.await(4, vim.uv.fs_open, path, flags, mode)
  return err, fd
end

---@async
---@param fd integer
---@return string? err
---@return boolean? success
function M.uv.fs_close(fd)
  local err, success = vim.async.await(2, vim.uv.fs_close, fd)
  return err, success
end

---@async
---@param fd integer
---@param size integer
---@param offset? integer default: -1 (current file position)
---@return string? err
---@return string data
function M.uv.fs_read(fd, size, offset)
  local err, data = vim.async.await(4, vim.uv.fs_read, fd, size, offset or -1)
  return err, data
end

---@async
---@param fd integer
---@param data string
---@param offset? integer default: -1 (current file position)
---@return string? err
---@return integer bytes
function M.uv.fs_write(fd, data, offset)
  local err, bytes = vim.async.await(4, vim.uv.fs_write, fd, data, offset or -1)
  return err, bytes
end

---@async
---@param path string
---@return string? err
---@return boolean? success
function M.uv.fs_unlink(path)
  local err, success = vim.async.await(2, vim.uv.fs_unlink, path)
  return err, success
end

---@async
---@param path string
---@return string? err
---@return string? path
function M.uv.fs_realpath(path)
  local err, realpath = vim.async.await(2, vim.uv.fs_realpath, path)
  return err, realpath
end

return M
