---@diagnostic disable: invisible
local Database = require "frecency.database"
local FS = require "frecency.fs"
local EntryMaker = require "frecency.entry_maker"
local Finder = require "frecency.finder"
local Picker = require "frecency.picker"
local Recency = require "frecency.recency"
local util = require "frecency.tests.util"

local function prepare(files, opts)
  opts = vim.tbl_extend("force", {
    ignore_patterns = {},
    __files = {
      "lua/hoge/fuga.lua",
      "lua/hoge/hoho.lua",
      "lua/hoge/fufu.lua",
      "lua/hogehoge.lua",
      "lua/fugafuga.lua",
    },
    __clear_db = true,
  }, opts or {})
  local dir, close = util.make_tree(files)
  if opts.__clear_db then
    dir:joinpath("file_frecency.sqlite3"):rm()
  end
  opts.root = dir
  local database = Database.new(opts)
  local fs = FS.new(opts)
  local entry_maker = EntryMaker.new(fs, opts)
  local finder = Finder.new(entry_maker, fs, opts)
  return Picker.new(database, finder, fs, Recency.new(), opts), dir, close
end

describe("finder", function()
  describe("create_fn", function()
    describe("with default chunk_size", function()
      local files = { "hoge1.txt", "hoge2.txt" }
      local picker, dir, close = prepare(files, {})
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
      close()
    end)

    describe("with small chunk_size", function()
      local files = { "hoge1.txt", "hoge2.txt", "hoge3.txt", "hoge4.txt", "hoge5.txt", "hoge6.txt" }
      local picker, dir, close = prepare(files, { chunk_size = 2 })
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
      close()
    end)

    describe("with initial_results", function()
      local files = { "hoge1.txt", "hoge2.txt" }
      local picker, dir, close = prepare(files, {})
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
      close()
    end)
  end)
end)
