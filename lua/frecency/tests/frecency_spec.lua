-- HACK: This is needed because plenary.test_harness resets &rtp.
-- luacheck: push no max comment line length
-- https://github.com/nvim-lua/plenary.nvim/blob/663246936325062427597964d81d30eaa42ab1e4/lua/plenary/test_harness.lua#L86-L86
-- luacheck: pop
vim.opt.runtimepath:append(vim.env.TELESCOPE_PATH)

local util = require "frecency.tests.util"
local log = require "plenary.log"

local filepath = util.filepath
local make_epoch = util.make_epoch
local make_register = util.make_register
local with_fake_register = util.with_fake_register
local with_files = util.with_files

describe("frecency", function()
  describe("register", function()
    describe("when opening files", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        local epoch1 = make_epoch "2023-07-29T00:00:00+09:00"
        local epoch2 = make_epoch "2023-07-29T01:00:00+09:00"
        -- HACK: This suspicious 'swapfile' setting is for avoiding E303.
        vim.o.swapfile = false
        register("hoge1.txt", epoch1)
        vim.o.swapfile = true
        register("hoge2.txt", epoch2)

        it("has valid records in DB", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
          assert.are.same({
            { count = 1, path = filepath(dir, "hoge2.txt"), score = 10, timestamps = { epoch2 } },
            { count = 1, path = filepath(dir, "hoge1.txt"), score = 10, timestamps = { epoch1 } },
          }, results)
        end)
      end)
    end)

    describe("when opening again", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        local epoch11 = make_epoch "2023-07-29T00:00:00+09:00"
        local epoch2 = make_epoch "2023-07-29T01:00:00+09:00"
        local epoch12 = make_epoch "2023-07-29T02:00:00+09:00"
        register("hoge1.txt", epoch11)
        register("hoge2.txt", epoch2)
        register("hoge1.txt", epoch12, true)

        it("increases the score", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T03:00:00+09:00")
          assert.are.same({
            { count = 2, path = filepath(dir, "hoge1.txt"), score = 40, timestamps = { epoch11, epoch12 } },
            { count = 1, path = filepath(dir, "hoge2.txt"), score = 10, timestamps = { epoch2 } },
          }, results)
        end)
      end)
    end)

    describe("when opening again but the same instance", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        local epoch11 = make_epoch "2023-07-29T00:00:00+09:00"
        local epoch2 = make_epoch "2023-07-29T01:00:00+09:00"
        local epoch12 = make_epoch "2023-07-29T02:00:00+09:00"
        register("hoge1.txt", epoch11)
        register("hoge2.txt", epoch2)
        register("hoge1.txt", epoch12)

        it("does not increase the score", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T03:00:00+09:00")
          assert.are.same({
            { count = 1, path = filepath(dir, "hoge2.txt"), score = 10, timestamps = { epoch2 } },
            { count = 1, path = filepath(dir, "hoge1.txt"), score = 10, timestamps = { epoch11 } },
          }, results)
        end)
      end)
    end)

    describe("when opening more than 10 times", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        local epoch11 = make_epoch "2023-07-29T00:00:00+09:00"
        local epoch12 = make_epoch "2023-07-29T00:01:00+09:00"
        register("hoge1.txt", epoch11)
        register("hoge1.txt", epoch12, true)

        local epoch201 = make_epoch "2023-07-29T00:00:00+09:00"
        local epoch202 = make_epoch "2023-07-29T00:01:00+09:00"
        local epoch203 = make_epoch "2023-07-29T00:02:00+09:00"
        local epoch204 = make_epoch "2023-07-29T00:03:00+09:00"
        local epoch205 = make_epoch "2023-07-29T00:04:00+09:00"
        local epoch206 = make_epoch "2023-07-29T00:05:00+09:00"
        local epoch207 = make_epoch "2023-07-29T00:06:00+09:00"
        local epoch208 = make_epoch "2023-07-29T00:07:00+09:00"
        local epoch209 = make_epoch "2023-07-29T00:08:00+09:00"
        local epoch210 = make_epoch "2023-07-29T00:09:00+09:00"
        local epoch211 = make_epoch "2023-07-29T00:10:00+09:00"
        local epoch212 = make_epoch "2023-07-29T00:11:00+09:00"
        register("hoge2.txt", epoch201)
        register("hoge2.txt", epoch202, true)
        register("hoge2.txt", epoch203, true)
        register("hoge2.txt", epoch204, true)
        register("hoge2.txt", epoch205, true)
        register("hoge2.txt", epoch206, true)
        register("hoge2.txt", epoch207, true)
        register("hoge2.txt", epoch208, true)
        register("hoge2.txt", epoch209, true)
        register("hoge2.txt", epoch210, true)
        register("hoge2.txt", epoch211, true)
        register("hoge2.txt", epoch212, true)

        it("calculates score from the recent 10 times", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T00:12:00+09:00")
          assert.are.same({
            {
              count = 12,
              path = filepath(dir, "hoge2.txt"),
              score = 12 * (10 * 100) / 10,
              timestamps = {
                epoch203,
                epoch204,
                epoch205,
                epoch206,
                epoch207,
                epoch208,
                epoch209,
                epoch210,
                epoch211,
                epoch212,
              },
            },
            {
              count = 2,
              path = filepath(dir, "hoge1.txt"),
              score = 2 * (2 * 100) / 10,
              timestamps = { epoch11, epoch12 },
            },
          }, results)
        end)
      end)
    end)

    describe("when ignore_register is set", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, {
        ignore_register = function(bufnr)
          local _, bufname = pcall(vim.api.nvim_buf_get_name, bufnr)
          local should_ignore = not not (bufname and bufname:find "hoge2%.txt$")
          log.debug { bufnr = bufnr, bufname = bufname, should_ignore = should_ignore }
          return should_ignore
        end,
      }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        local epoch1 = make_epoch "2023-07-29T00:00:00+09:00"
        register("hoge1.txt", epoch1)
        local epoch2 = make_epoch "2023-07-29T01:00:00+09:00"
        register("hoge2.txt", epoch2)
        it("ignores the file the func returns true", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
          assert.are.same({
            { count = 1, path = filepath(dir, "hoge1.txt"), score = 10, timestamps = { epoch1 } },
          }, results)
        end)
      end)
    end)
  end)

  describe("benchmark", function()
    describe("after registered over >5000 files", function()
      with_files({}, function(frecency, finder, dir)
        with_fake_register(frecency, dir, function(register)
          -- TODO: 6000 records is too many to use with native?
          -- local file_count = 6000
          local file_count = 600
          if not os.getenv "CI" then
            log.info "It works not on CI. Files is decreased into 10 count."
            file_count = 10
          end
          local expected = {}
          log.info(("making %d files and register them"):format(file_count))
          for i = 1, file_count do
            local file = ("hoge%08d.txt"):format(i)
            table.insert(expected, { count = 1, path = filepath(dir, file), score = 10 })
            -- HACK: disable log because it fails with too many logging
            log.new({ level = "info" }, true)
            register(file, make_epoch "2023-07-29T00:00:00+09:00")
            log.new({}, true)
          end
          local results = vim
            .iter(finder:get_results(nil, make_epoch "2023-07-29T00:01:00+09:00"))
            :map(function(result)
              result.timestamps = nil
              return result
            end)
            :totable()
          table.sort(results, function(a, b)
            return a.path < b.path
          end)

          it("returns valid response", function()
            assert.are.same(expected, results)
          end)
        end)
      end)
    end)
  end)

  describe("delete", function()
    describe("when file exists", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        local epoch1 = make_epoch "2023-07-29T00:00:00+09:00"
        local epoch2 = make_epoch "2023-07-29T00:01:00+09:00"
        register("hoge1.txt", epoch1)
        register("hoge2.txt", epoch2)

        it("deletes the file successfully", function()
          local path = filepath(dir, "hoge2.txt")
          local result
          ---@diagnostic disable-next-line: duplicate-set-field, invisible
          frecency.notify = function(self, fmt, ...)
            ---@diagnostic disable-next-line: invisible
            vim.notify(self:message(fmt, ...))
            result = true
          end
          frecency:delete(path)
          assert.are.same(result, true)
        end)

        it("returns valid results", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
          assert.are.same({
            { count = 1, path = filepath(dir, "hoge1.txt"), score = 10, timestamps = { epoch1 } },
          }, results)
        end)
      end)
    end)
  end)

  describe("query", function()
    with_files({ "hoge1.txt", "hoge2.txt", "hoge3.txt", "hoge4.txt" }, function(frecency, _, dir)
      local register = make_register(frecency, dir)
      local epoch11 = make_epoch "2023-07-29T00:00:00+09:00"
      local epoch2 = make_epoch "2023-07-29T00:01:00+09:00"
      local epoch12 = make_epoch "2023-07-29T00:02:00+09:00"
      local epoch31 = make_epoch "2023-07-29T00:03:00+09:00"
      local epoch13 = make_epoch "2023-07-29T00:04:00+09:00"
      local epoch32 = make_epoch "2023-07-29T00:05:00+09:00"
      local epoch4 = make_epoch "2023-07-29T00:06:00+09:00"
      register("hoge1.txt", epoch11)
      register("hoge2.txt", epoch2)
      register("hoge1.txt", epoch12, true)
      register("hoge3.txt", epoch31)
      register("hoge1.txt", epoch13, true)
      register("hoge3.txt", epoch32, true)
      register("hoge4.txt", epoch4)

      for _, c in ipairs {
        {
          desc = "with no opts",
          opts = nil,
          results = {
            filepath(dir, "hoge1.txt"),
            filepath(dir, "hoge3.txt"),
            filepath(dir, "hoge2.txt"),
            filepath(dir, "hoge4.txt"),
          },
        },
        {
          desc = "with an empty opts",
          opts = {},
          results = {
            filepath(dir, "hoge1.txt"),
            filepath(dir, "hoge3.txt"),
            filepath(dir, "hoge2.txt"),
            filepath(dir, "hoge4.txt"),
          },
        },
        {
          desc = "with limit",
          opts = { limit = 3 },
          results = {
            filepath(dir, "hoge1.txt"),
            filepath(dir, "hoge3.txt"),
            filepath(dir, "hoge2.txt"),
          },
        },
        {
          desc = "with limit, direction",
          opts = { direction = "asc", limit = 3 },
          results = {
            filepath(dir, "hoge2.txt"),
            filepath(dir, "hoge4.txt"),
            filepath(dir, "hoge3.txt"),
          },
        },
        {
          desc = "with limit, direction, order",
          opts = { direction = "asc", limit = 3, order = "path" },
          results = {
            filepath(dir, "hoge1.txt"),
            filepath(dir, "hoge2.txt"),
            filepath(dir, "hoge3.txt"),
          },
        },
        {
          desc = "with limit, direction, order, record",
          opts = { direction = "asc", limit = 3, order = "path", record = true },
          results = {
            { count = 3, path = filepath(dir, "hoge1.txt"), score = 90, timestamps = { epoch11, epoch12, epoch13 } },
            { count = 1, path = filepath(dir, "hoge2.txt"), score = 10, timestamps = { epoch2 } },
            { count = 2, path = filepath(dir, "hoge3.txt"), score = 40, timestamps = { epoch31, epoch32 } },
          },
        },
      } do
        describe(c.desc, function()
          it("returns valid results", function()
            assert.are.same(c.results, frecency:query(c.opts, make_epoch "2023-07-29T04:00:00+09:00"))
          end)
        end)
      end
    end)
  end)
end)
