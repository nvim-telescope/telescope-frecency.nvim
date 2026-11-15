local async = require "frecency.async"

---@param name string
---@return string
local function tempfile(name)
  return vim.fs.joinpath(vim.fn.tempname(), name)
end

describe("frecency.async", function()
  describe("channel.mpsc", function()
    it("returns values sent before recv() in FIFO order", function()
      local values = async.block_on(function()
        local tx, rx = async.channel.mpsc()
        tx.send "first"
        tx.send "second"
        return { rx.recv(), rx.recv() }
      end)
      assert.are.same({ "first", "second" }, values)
    end)

    it("suspends recv() until a value arrives", function()
      local value = async.block_on(function()
        local tx, rx = async.channel.mpsc()
        vim.defer_fn(function()
          tx.send "late"
        end, 10)
        return rx.recv()
      end)
      assert.are.same("late", value)
    end)

    it("passes nil through without ending the stream", function()
      local first, second_is_nil, third = async.block_on(function()
        local tx, rx = async.channel.mpsc()
        tx.send "before"
        tx.send(nil)
        tx.send "after"
        local a, b, c = rx.recv(), rx.recv(), rx.recv()
        return a, b == nil, c
      end)
      assert.are.same("before", first)
      assert.is_true(second_is_nil)
      assert.are.same("after", third)
    end)

    it("accepts send() from a fast event context", function()
      local sent_in_fast_event, value = async.block_on(function()
        local tx, rx = async.channel.mpsc()
        local in_fast_event
        local timer = assert(vim.uv.new_timer())
        timer:start(10, 0, function()
          in_fast_event = vim.in_fast_event()
          tx.send "from timer"
          timer:close()
        end)
        local received = rx.recv()
        return in_fast_event, received
      end)
      assert.is_true(sent_in_fast_event)
      assert.are.same("from timer", value)
    end)

    it("serves multiple producers", function()
      local values = async.block_on(function()
        local tx, rx = async.channel.mpsc()
        for i = 1, 3 do
          async.void(function()
            async.sleep(i * 10)
            tx.send(i)
          end)()
        end
        return { rx.recv(), rx.recv(), rx.recv() }
      end)
      assert.are.same({ 1, 2, 3 }, values)
    end)
  end)

  describe("join", function()
    it("keeps the order of the input, not the completion order", function()
      local results = async.block_on(function()
        return async.join {
          function()
            async.sleep(30)
            return "slow"
          end,
          function()
            return "fast"
          end,
        }
      end)
      assert.are.same({ { "slow" }, { "fast" } }, results)
    end)

    it("runs the functions concurrently", function()
      local elapsed = async.block_on(function()
        local start = vim.uv.hrtime()
        async.join {
          function()
            async.sleep(50)
          end,
          function()
            async.sleep(50)
          end,
        }
        return (vim.uv.hrtime() - start) / 1e6
      end)
      assert.is_true(elapsed < 100)
    end)

    it("caps concurrency with limit", function()
      local max_running = async.block_on(function()
        local running, max = 0, 0
        local fns = {}
        for _ = 1, 6 do
          fns[#fns + 1] = function()
            running = running + 1
            max = math.max(max, running)
            async.sleep(10)
            running = running - 1
          end
        end
        async.join(fns, 2)
        return max
      end)
      assert.are.same(2, max_running)
    end)
  end)

  describe("uv", function()
    it("round-trips a file through open / write / close / read / unlink", function()
      local path = tempfile "async_spec.txt"
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      local read, err_after_unlink = async.block_on(function()
        local err, fd = async.uv.fs_open(path, "w", tonumber("644", 8))
        assert(not err, err)
        assert(not async.uv.fs_write(fd, "hello"))
        assert(not async.uv.fs_close(fd))
        local stat
        err, stat = async.uv.fs_stat(path)
        assert(not err, err)
        err, fd = async.uv.fs_open(path, "r", tonumber("644", 8))
        assert(not err, err)
        local data
        err, data = async.uv.fs_read(fd, stat.size)
        assert(not err, err)
        assert(not async.uv.fs_close(fd))
        assert(not async.uv.fs_unlink(path))
        return data, (async.uv.fs_stat(path))
      end)
      assert.are.same("hello", read)
      assert.is_not.Nil(err_after_unlink) -- the file is gone: fs_stat() reports ENOENT
    end)

    it("reports errors as the first return value", function()
      local err, stat = async.block_on(function()
        return async.uv.fs_stat(tempfile "does_not_exist")
      end)
      assert.is_not.Nil(err)
      assert.is.Nil(stat)
    end)
  end)

  describe("scheduler", function()
    it("returns from a fast event context to the main loop", function()
      local before, after = async.block_on(function()
        async.uv.fs_stat(vim.fn.tempname())
        local in_fast_event = vim.in_fast_event()
        async.scheduler()
        return in_fast_event, vim.in_fast_event()
      end)
      assert.is_true(before)
      assert.is_false(after)
    end)
  end)

  describe("void", function()
    it("runs a task from synchronous code", function()
      local done = false
      async.void(function()
        async.sleep(10)
        done = true
      end)()
      vim.wait(1000, function()
        return done
      end)
      assert.is_true(done)
    end)

    it("does not make the calling task wait for it", function()
      local finished = async.block_on(function()
        local child_finished = false
        async.void(function()
          async.sleep(50)
          child_finished = true
        end)()
        async.sleep(10)
        return child_finished
      end)
      assert.is_false(finished)
    end)
  end)
end)
