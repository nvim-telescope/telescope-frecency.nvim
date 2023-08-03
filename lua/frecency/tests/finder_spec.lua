---@diagnostic disable: invisible
local Database = require "frecency.database"
local FS = require "frecency.fs"
local EntryMaker = require "frecency.entry_maker"
local Finder = require "frecency.finder"
local Picker = require "frecency.picker"
local Recency = require "frecency.recency"
local WebDevicons = require "frecency.web_devicons"
local util = require "frecency.tests.util"

---@param files string[]
---@param opts table
---@param callback fun(picker: FrecencyPicker, dir: PlenaryPath): nil
local function with_files(files, opts, callback)
  opts = vim.tbl_extend("force", {
    ignore_patterns = {},
    filter_delimiter = ":",
  }, opts or {})
  local dir, close = util.make_tree(files)
  opts.root = dir
  local fs = FS.new(opts)
  local database = Database.new(fs, opts)
  local web_devicons = WebDevicons.new(true)
  local entry_maker = EntryMaker.new(fs, web_devicons, opts)
  local finder = Finder.new(entry_maker, fs, opts)
  local picker = Picker.new(database, finder, fs, Recency.new(), opts)
  callback(picker, dir)
  close()
end

describe("finder", function()
  describe("create_fn", function()
    ---@diagnostic disable-next-line: param-type-mismatch
    if vim.version.eq(vim.version(), "0.9.0") then
      it("skips these tests for v0.9.0", function()
        assert.are.same(true, true)
      end)
      return
    end

    describe("with default chunk_size", function()
      local files = { "hoge1.txt", "hoge2.txt" }
      with_files(files, {}, function(picker, dir)
        local fn = picker.finder:create_fn({}, dir.filename)
        it("returns the whole results", function()
          assert.are.same({
            { path = dir:joinpath("file_frecency.sqlite3").filename, score = 0 },
            { path = dir:joinpath("hoge1.txt").filename, score = 0 },
            { path = dir:joinpath("hoge2.txt").filename, score = 0 },
          }, fn())
        end)
        it("returns the same results", function()
          assert.are.same({
            { path = dir:joinpath("file_frecency.sqlite3").filename, score = 0 },
            { path = dir:joinpath("hoge1.txt").filename, score = 0 },
            { path = dir:joinpath("hoge2.txt").filename, score = 0 },
          }, fn())
        end)
      end)
    end)

    describe("with small chunk_size", function()
      local files = { "hoge1.txt", "hoge2.txt", "hoge3.txt", "hoge4.txt", "hoge5.txt", "hoge6.txt" }
      with_files(files, { chunk_size = 2 }, function(picker, dir)
        local fn = picker.finder:create_fn({}, dir.filename)
        it("returns the 1st chunk", function()
          assert.are.same({
            { path = dir:joinpath("file_frecency.sqlite3").filename, score = 0 },
            { path = dir:joinpath("hoge1.txt").filename, score = 0 },
          }, fn())
        end)
        it("returns the 2nd chunk", function()
          assert.are.same({
            { path = dir:joinpath("file_frecency.sqlite3").filename, score = 0 },
            { path = dir:joinpath("hoge1.txt").filename, score = 0 },
            { path = dir:joinpath("hoge2.txt").filename, score = 0 },
            { path = dir:joinpath("hoge3.txt").filename, score = 0 },
          }, fn())
        end)
        it("returns the 3rd chunk", function()
          assert.are.same({
            { path = dir:joinpath("file_frecency.sqlite3").filename, score = 0 },
            { path = dir:joinpath("hoge1.txt").filename, score = 0 },
            { path = dir:joinpath("hoge2.txt").filename, score = 0 },
            { path = dir:joinpath("hoge3.txt").filename, score = 0 },
            { path = dir:joinpath("hoge4.txt").filename, score = 0 },
            { path = dir:joinpath("hoge5.txt").filename, score = 0 },
          }, fn())
        end)
        it("returns the 4th chunk", function()
          assert.are.same({
            { path = dir:joinpath("file_frecency.sqlite3").filename, score = 0 },
            { path = dir:joinpath("hoge1.txt").filename, score = 0 },
            { path = dir:joinpath("hoge2.txt").filename, score = 0 },
            { path = dir:joinpath("hoge3.txt").filename, score = 0 },
            { path = dir:joinpath("hoge4.txt").filename, score = 0 },
            { path = dir:joinpath("hoge5.txt").filename, score = 0 },
            { path = dir:joinpath("hoge6.txt").filename, score = 0 },
          }, fn())
        end)
        it("returns the same results", function()
          assert.are.same({
            { path = dir:joinpath("file_frecency.sqlite3").filename, score = 0 },
            { path = dir:joinpath("hoge1.txt").filename, score = 0 },
            { path = dir:joinpath("hoge2.txt").filename, score = 0 },
            { path = dir:joinpath("hoge3.txt").filename, score = 0 },
            { path = dir:joinpath("hoge4.txt").filename, score = 0 },
            { path = dir:joinpath("hoge5.txt").filename, score = 0 },
            { path = dir:joinpath("hoge6.txt").filename, score = 0 },
          }, fn())
        end)
      end)
    end)

    describe("with initial_results", function()
      local files = { "hoge1.txt", "hoge2.txt" }
      with_files(files, {}, function(picker, dir)
        local fn = picker.finder:create_fn({
          { path = "hogefuga", score = 50 },
          { path = "fugahoge", score = 100 },
        }, dir.filename)
        it("returns the whole results", function()
          assert.are.same({
            { path = "hogefuga", score = 50 },
            { path = "fugahoge", score = 100 },
            { path = dir:joinpath("file_frecency.sqlite3").filename, score = 0 },
            { path = dir:joinpath("hoge1.txt").filename, score = 0 },
            { path = dir:joinpath("hoge2.txt").filename, score = 0 },
          }, fn())
        end)
        it("returns the same results", function()
          assert.are.same({
            { path = "hogefuga", score = 50 },
            { path = "fugahoge", score = 100 },
            { path = dir:joinpath("file_frecency.sqlite3").filename, score = 0 },
            { path = dir:joinpath("hoge1.txt").filename, score = 0 },
            { path = dir:joinpath("hoge2.txt").filename, score = 0 },
          }, fn())
        end)
      end)
    end)

    describe("with ignore_patterns", function()
      with_files(
        { "hoge/fuga1.txt", "hoge/fuga2.txt", "hoge1.txt", "hoge2.txt", "fuga3.txt" },
        { ignore_patterns = { "*/hoge/*" } },
        function(picker, dir)
          local fn = picker.finder:create_fn({}, dir.filename)
          it("returns files without patterns", function()
            assert.are.same({
              { path = dir:joinpath("file_frecency.sqlite3").filename, score = 0 },
              { path = dir:joinpath("fuga3.txt").filename, score = 0 },
              { path = dir:joinpath("hoge1.txt").filename, score = 0 },
              { path = dir:joinpath("hoge2.txt").filename, score = 0 },
            }, fn())
          end)
        end
      )
    end)
  end)
end)
