---@diagnostic disable: invisible
local Frecency = require "frecency.frecency"
local util = require "frecency.tests.util"
local Path = require "plenary.path"
local log = require "plenary.log"

local function prepare(files)
  local dir, close = util.make_tree(files)
  return Frecency.new { db_root = dir.filename }, dir, close
end

local function filepath(dir, file)
  return dir:joinpath(file):absolute()
end

---@param frecency Frecency
---@param dir PlenaryPath
---@return fun(file: string, datetime: string, reset: boolean?): nil
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

---comment
---@param frecency Frecency
---@param dir PlenaryPath
---@return fun(file: string, datetime: string): nil faked_register
---@return fun(): nil restore
local function make_fake_register(frecency, dir)
  local bufnr = 0
  local buffers = {}
  local original_nvim_buf_get_name = vim.api.nvim_buf_get_name
  ---@diagnostic disable-next-line: redefined-local, duplicate-set-field
  vim.api.nvim_buf_get_name = function(bufnr)
    return buffers[bufnr]
  end
  return function(file, datetime)
    local path = filepath(dir, file)
    Path.new(path):touch()
    bufnr = bufnr + 1
    buffers[bufnr] = path
    frecency:register(bufnr, datetime)
  end, function()
    vim.api.nvim_buf_get_name = original_nvim_buf_get_name
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

  describe("benchmark", function()
    describe("after registered over >5000 files", function()
      local frecency, dir, close = prepare {}
      local faked_register, restore = make_fake_register(frecency, dir)
      local file_count = 6000
      local expected = {}
      for i = 1, file_count do
        local file = ("hoge%08d.txt"):format(i)
        table.insert(expected, { count = 1, id = i, path = filepath(dir, file), score = 10 })
        faked_register(file, "2023-07-29T00:00:00+09:00")
      end
      local start = os.clock()
      local results = frecency.picker:fetch_results(nil, "2023-07-29T00:01:00+09:00")
      table.sort(results, function(a, b)
        return a.path < b.path
      end)
      local elapsed = os.clock() - start
      log.info(("it takes %f seconds in fetching all results"):format(elapsed))
      it("returns appropriate latency (<1.0 second)", function()
        assert.are.is_true(elapsed < 1.0)
      end)
      it("returns valid response", function()
        assert.are.same(expected, results)
      end)
      close()
      restore()
    end)
  end)
end)
