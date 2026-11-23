---@diagnostic disable: invisible, undefined-field
local State = require "frecency.state"
local util = require "frecency.tests.util"

local make_epoch = util.make_epoch
local make_register = util.make_register
local with_files = util.with_files

-- Run a find the way telescope's picker does: in a |vim.async| task of its own.
-- `on_result` may return true to stop, as the picker does for a stale find.
---@param finder FrecencyFinder
---@param on_result? fun(task: vim.async.Task, entry: FrecencyEntry): boolean?
---@return string[] basenames the picker was handed; the DB files that share the
---workspace directory are filtered out
---@return boolean completed
---@return boolean? ok `false` when the task failed or was closed, `nil` when it
---did not finish in time
local function find(finder, on_result)
  local received = {}
  local completed = false
  ---@type vim.async.Task
  local task
  task = vim.async.run(function()
    finder("", function(entry)
      local name = vim.fs.basename(entry.filename)
      if name:match "%.txt$" then
        received[#received + 1] = name
      end
      return on_result and on_result(task, entry)
    end, function()
      completed = true
    end)
  end)
  vim.wait(5000, function()
    return completed or task:completed()
  end, 20)
  table.sort(received)
  ---@type boolean?
  local ok
  if task:completed() then
    ok = vim.async.run(vim.async.pawait, task):wait(1000)
  end
  return received, completed, ok
end

describe("frecency.finder", function()
  describe("when driven like the picker does", function()
    with_files({ "hoge1.txt", "hoge2.txt", "fuga1.txt" }, function(frecency, _, dir)
      local register = make_register(frecency, dir)
      register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
      register("hoge2.txt", make_epoch "2023-07-29T00:01:00+09:00")

      frecency.picker.state = State.new()
      local finder = frecency.picker:finder({}, { dir.filename }, "CWD")
      finder:start()
      local received, completed = find(finder)

      it("calls process_complete()", function()
        assert.is_true(completed)
      end)

      it("streams both the indexed entries and the unindexed ones", function()
        assert.are.same({ "fuga1.txt", "hoge1.txt", "hoge2.txt" }, received)
      end)
    end)
  end)

  describe("when the workspace is scanned with Lua", function()
    with_files({ "hoge1.txt", "fuga1.txt" }, { workspace_scan_cmd = "LUA" }, function(frecency, _, dir)
      local register = make_register(frecency, dir)
      register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")

      frecency.picker.state = State.new()
      local finder = frecency.picker:finder({}, { dir.filename }, "CWD")
      finder:start()
      local received, completed = find(finder)

      it("calls process_complete()", function()
        assert.is_true(completed)
      end)

      it("streams both the indexed entries and the unindexed ones", function()
        assert.are.same({ "fuga1.txt", "hoge1.txt" }, received)
      end)
    end)
  end)

  -- The picker closes a find's task when the prompt changes, and the finder
  -- stops at its next wait. The next find must pick up where it stopped.
  describe("when a find is closed by a prompt change", function()
    with_files({ "hoge1.txt", "hoge2.txt", "fuga1.txt" }, function(frecency, _, dir)
      local register = make_register(frecency, dir)
      register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
      register("hoge2.txt", make_epoch "2023-07-29T00:01:00+09:00")

      frecency.picker.state = State.new()
      local finder = frecency.picker:finder({}, { dir.filename }, "CWD")
      finder:start()
      local _, first_completed, first_ok = find(finder, function(task)
        task:close()
      end)
      local received, completed = find(finder)

      it("stops the closed find", function()
        assert.is_false(first_completed)
        assert.is_false(first_ok)
      end)

      it("streams every entry exactly once in the next find", function()
        assert.is_true(completed)
        assert.are.same({ "fuga1.txt", "hoge1.txt", "hoge2.txt" }, received)
      end)
    end)
  end)
end)
