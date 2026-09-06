---@diagnostic disable: invisible, undefined-field
local State = require "frecency.state"
local util = require "frecency.tests.util"
-- The picker drives the finder from telescope's async runtime, and this spec
-- does the same: the finder's consumer side has to yield the way that runtime
-- expects, which is not the same as |vim.async|.
local telescope_async = require "neoplen.async"

local make_epoch = util.make_epoch
local make_register = util.make_register
local with_files = util.with_files

---@param finder FrecencyFinder
---@return string[] basenames the picker was handed; the DB files that share the
---workspace directory are filtered out
---@return boolean completed
local function drive(finder)
  local received = {}
  local completed = false
  finder:start()
  telescope_async.void(function()
    finder("", function(entry)
      local name = vim.fs.basename(entry.filename)
      if name:match "%.txt$" then
        received[#received + 1] = name
      end
    end, function()
      completed = true
    end)
  end)()
  vim.wait(5000, function()
    return completed
  end, 20)
  table.sort(received)
  return received, completed
end

describe("frecency.finder", function()
  describe("when driven like the picker does", function()
    with_files({ "hoge1.txt", "hoge2.txt", "fuga1.txt" }, function(frecency, _, dir)
      local register = make_register(frecency, dir)
      register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
      register("hoge2.txt", make_epoch "2023-07-29T00:01:00+09:00")

      frecency.picker.state = State.new()
      local finder = frecency.picker:finder({}, { dir.filename }, "CWD")
      local received, completed = drive(finder)

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
      local received, completed = drive(finder)

      it("calls process_complete()", function()
        assert.is_true(completed)
      end)

      it("streams both the indexed entries and the unindexed ones", function()
        assert.are.same({ "fuga1.txt", "hoge1.txt" }, received)
      end)
    end)
  end)
end)
