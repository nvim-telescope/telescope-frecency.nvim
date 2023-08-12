---@diagnostic disable: invisible
local AsyncFinder = require "frecency.async_finder"
local State = require "frecency.state"
local FS = require "frecency.fs"
local EntryMaker = require "frecency.entry_maker"
local WebDevicons = require "frecency.web_devicons"
local util = require "frecency.tests.util"

---@param files string[]
---@param initial_results string[]
---@param callback fun(async_finder: FrecencyAsyncFinder, dir: PlenaryPath): nil
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
  local initials = vim.tbl_map(function(v)
    return { path = (dir / v):absolute() }
  end, initial_results)
  local async_finder = AsyncFinder.new(State.new(), fs, dir:absolute(), entry_maker, initials)
  callback(async_finder, dir)
  close()
end

describe("async_finder", function()
  local function run(async_finder)
    local count = { process_result = 0, process_complete = 0 }
    local results = {}
    async_finder("", function(result)
      count.process_result = count.process_result + 1
      table.insert(results, result.filename)
    end, function()
      count.process_complete = count.process_complete + 1
    end)
    return count, results
  end

  describe("with no initial_results", function()
    with_files({ "hoge1.txt", "hoge2.txt" }, {}, function(async_finder, dir)
      describe("when run at the first time", function()
        local count, results = run(async_finder)
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
        local count, results = run(async_finder)
        it("called process_result() at 2 times", function()
          assert.are.same(2, count.process_result)
        end)
        it("called process_complete() at 1 time", function()
          assert.are.same(1, count.process_complete)
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

  describe("with initial_results", function()
    with_files({ "fuga1.txt", "hoge1.txt", "hoge2.txt" }, { "fuga1.txt" }, function(async_finder, dir)
      local count, results = run(async_finder)
      it("called process_result() at 3 times", function()
        assert.are.same(3, count.process_result)
      end)
      it("called process_complete() at 1 time", function()
        assert.are.same(1, count.process_complete)
      end)
      it("returns the same results without duplications", function()
        assert.are.same({
          dir:joinpath("fuga1.txt").filename,
          dir:joinpath("hoge1.txt").filename,
          dir:joinpath("hoge2.txt").filename,
        }, results)
      end)
    end)
  end)
end)
