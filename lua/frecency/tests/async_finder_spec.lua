---@diagnostic disable: invisible
local AsyncFinder = require "frecency.async_finder"
local FS = require "frecency.fs"
local EntryMaker = require "frecency.entry_maker"
local WebDevicons = require "frecency.web_devicons"
local util = require "frecency.tests.util"

---@param files string[]
---@param initial_results string[]
---@param callback fun(async_finder: AsyncFinder, dir: PlenaryPath): nil
local function with_files(files, initial_results, callback)
  local dir, close = util.make_tree(files)
  local fs = FS.new { ignore_patterns = {} }
  local web_devicons = WebDevicons.new(true)
  local function filepath_formatter()
    return function(name)
      return name
    end
  end
  local entry_maker = EntryMaker.new(fs, web_devicons, { show_filter_column = false, show_scores = false })
    :create(filepath_formatter, dir:absolute())
  local async_finder = AsyncFinder.new(fs, dir:absolute(), entry_maker, initial_results)
  callback(async_finder, dir)
  close()
end

describe("async_finder", function()
  ---@diagnostic disable-next-line: param-type-mismatch
  if vim.version.eq(vim.version(), "0.9.0") then
    it("skips these tests for v0.9.0", function()
      assert.are.same(true, true)
    end)
    return
  end

  describe("with no initial_results", function()
    local files = { "hoge1.txt", "hoge2.txt" }
    with_files(files, {}, function(async_finder, dir)
      local count = { process_result = 0, process_complete = 0 }
      local results
      local function run()
        results = {}
        async_finder("", function(result)
          count.process_result = count.process_result + 1
          table.insert(results, result.filename)
        end, function()
          count.process_complete = count.process_complete + 1
        end)
      end

      describe("when run at the first time", function()
        run()
        it("called process_result() at 2 times", function()
          assert.are.same(2, count.process_result)
        end)
        it("called process_complete() at 1 time", function()
          assert.are.same(1, count.process_complete)
        end)
        it("returns the whole results", function()
          assert.are.same({
            dir:joinpath("hoge1.txt").filename,
            dir:joinpath("hoge2.txt").filename,
          }, results)
        end)
      end)

      describe("when run again", function()
        run()
        it("called process_result() at 4 times", function()
          assert.are.same(4, count.process_result)
        end)
        it("called process_complete() at 1 time", function()
          assert.are.same(2, count.process_complete)
        end)
        it("returns the same results", function()
          assert.are.same({
            dir:joinpath("hoge1.txt").filename,
            dir:joinpath("hoge2.txt").filename,
          }, results)
        end)
      end)
    end)
  end)
end)
