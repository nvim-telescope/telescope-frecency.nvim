---@diagnostic disable: invisible
local Frecency = require "frecency.frecency"
local util = require "frecency.tests.util"

local function prepare(files)
  local dir, close = util.make_tree(files)
  return Frecency.new { db_root = dir.filename }, dir, close
end

local function filepath(dir, file)
  return dir:joinpath(file):absolute()
end

local function make_register(frecency, dir)
  return function(file, datetime, reset)
    local path = filepath(dir, file)
    vim.cmd.edit(path)
    local bufnr = vim.fn.bufnr(path)
    if reset then
      frecency.buf_registered[bufnr] = nil
    end
    frecency:register(bufnr, datetime)
  end
end

describe("frecency", function()
  describe("register", function()
    describe("when opening files", function()
      local frecency, dir, close = prepare { "hoge1.txt", "hoge2.txt" }
      local register = make_register(frecency, dir)
      register("hoge1.txt", "2023-07-29T00:00:00+09:00")
      register("hoge2.txt", "2023-07-29T01:00:00+09:00")
      it("has valid records in DB", function()
        local results = frecency.picker:fetch_results(nil, "2023-07-29T02:00:00+09:00")
        assert.are.same({
          { count = 1, id = 1, path = filepath(dir, "hoge1.txt"), score = 10 },
          { count = 1, id = 2, path = filepath(dir, "hoge2.txt"), score = 10 },
        }, results)
      end)
      close()
    end)

    describe("when opening again", function()
      local frecency, dir, close = prepare { "hoge1.txt", "hoge2.txt" }
      local register = make_register(frecency, dir)
      register("hoge1.txt", "2023-07-29T00:00:00+09:00")
      register("hoge2.txt", "2023-07-29T01:00:00+09:00")
      register("hoge1.txt", "2023-07-29T02:00:00+09:00", true)
      it("increases the score", function()
        local results = frecency.picker:fetch_results(nil, "2023-07-29T03:00:00+09:00")
        assert.are.same({
          { count = 2, id = 1, path = filepath(dir, "hoge1.txt"), score = 40 },
          { count = 1, id = 2, path = filepath(dir, "hoge2.txt"), score = 10 },
        }, results)
      end)
      close()
    end)

    describe("when opening again but the same instance", function()
      local frecency, dir, close = prepare { "hoge1.txt", "hoge2.txt" }
      local register = make_register(frecency, dir)
      register("hoge1.txt", "2023-07-29T00:00:00+09:00")
      register("hoge2.txt", "2023-07-29T01:00:00+09:00")
      register("hoge1.txt", "2023-07-29T02:00:00+09:00")
      it("does not increase the score", function()
        local results = frecency.picker:fetch_results(nil, "2023-07-29T03:00:00+09:00")
        assert.are.same({
          { count = 1, id = 1, path = filepath(dir, "hoge1.txt"), score = 10 },
          { count = 1, id = 2, path = filepath(dir, "hoge2.txt"), score = 10 },
        }, results)
      end)
      close()
    end)

    describe("when opening more than 10 times", function()
      local frecency, dir, close = prepare { "hoge1.txt", "hoge2.txt" }
      local register = make_register(frecency, dir)
      register("hoge1.txt", "2023-07-29T00:00:00+09:00")
      register("hoge1.txt", "2023-07-29T00:01:00+09:00", true)
      register("hoge1.txt", "2023-07-29T00:02:00+09:00", true)
      register("hoge1.txt", "2023-07-29T00:03:00+09:00", true)
      register("hoge1.txt", "2023-07-29T00:04:00+09:00", true)
      register("hoge1.txt", "2023-07-29T00:05:00+09:00", true)
      register("hoge1.txt", "2023-07-29T00:06:00+09:00", true)
      register("hoge1.txt", "2023-07-29T00:07:00+09:00", true)
      register("hoge1.txt", "2023-07-29T00:08:00+09:00", true)
      register("hoge1.txt", "2023-07-29T00:09:00+09:00", true)
      register("hoge1.txt", "2023-07-29T00:10:00+09:00", true)
      register("hoge1.txt", "2023-07-29T00:11:00+09:00", true)
      it("calculates score from the recent 10 times", function()
        local results = frecency.picker:fetch_results(nil, "2023-07-29T00:12:00+09:00")
        assert.are.same({
          { count = 12, id = 1, path = filepath(dir, "hoge1.txt"), score = 12 * (10 * 100) / 10 },
        }, results)
      end)
      close()
    end)
  end)
end)
