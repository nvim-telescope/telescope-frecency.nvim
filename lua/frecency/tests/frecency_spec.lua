-- HACK: This is needed because plenary.test_harness resets &rtp.
-- https://github.com/nvim-lua/plenary.nvim/blob/663246936325062427597964d81d30eaa42ab1e4/lua/plenary/test_harness.lua#L86-L86
vim.opt.runtimepath:append(vim.env.TELESCOPE_PATH)

---@diagnostic disable: invisible, undefined-field
local Frecency = require "frecency.klass"
local Picker = require "frecency.picker"
local util = require "frecency.tests.util"
local log = require "plenary.log"
local Path = require "plenary.path"
local config = require "frecency.config"

---@param datetime string?
---@return integer
local function make_epoch(datetime)
  if not datetime then
    return os.time()
  end
  local tz_fix = datetime:gsub("+(%d%d):(%d%d)$", "+%1%2")
  return util.time_piece(tz_fix)
end

---@param files string[]
---@param cb_or_config table|fun(frecency: Frecency, finder: FrecencyFinder, dir: FrecencyPlenaryPath): nil
---@param callback? fun(frecency: Frecency, finder: FrecencyFinder, dir: FrecencyPlenaryPath): nil
---@return nil
local function with_files(files, cb_or_config, callback)
  local dir, close = util.make_tree(files)
  local cfg
  if type(cb_or_config) == "table" then
    cfg = vim.tbl_extend("force", { debug = true, db_root = dir.filename }, cb_or_config)
  else
    cfg = { debug = true, db_root = dir.filename }
    callback = cb_or_config
  end
  assert(callback)
  log.debug(cfg)
  config.setup(cfg)
  local frecency = Frecency.new()
  frecency.database.tbl:wait_ready()
  frecency.picker =
    Picker.new(frecency.database, frecency.entry_maker, frecency.fs, frecency.recency, { editing_bufnr = 0 })
  local finder = frecency.picker:finder {}
  callback(frecency, finder, dir)
  close()
end

local function filepath(dir, file)
  return dir:joinpath(file):absolute()
end

---@param frecency Frecency
---@param dir FrecencyPlenaryPath
---@return fun(file: string, epoch: integer, reset: boolean?): nil
local function make_register(frecency, dir)
  return function(file, epoch, reset)
    local path = filepath(dir, file)
    vim.cmd.edit(path)
    local bufnr = assert(vim.fn.bufnr(path))
    if reset then
      frecency.buf_registered[bufnr] = nil
    end
    frecency:register(bufnr, epoch)
  end
end

---@param frecency Frecency
---@param dir FrecencyPlenaryPath
---@param callback fun(register: fun(file: string, epoch?: integer): nil): nil
---@return nil
local function with_fake_register(frecency, dir, callback)
  local bufnr = 0
  local buffers = {}
  local original_nvim_buf_get_name = vim.api.nvim_buf_get_name
  ---@diagnostic disable-next-line: redefined-local, duplicate-set-field
  vim.api.nvim_buf_get_name = function(bufnr)
    return buffers[bufnr]
  end
  ---@param file string
  ---@param epoch integer
  local function register(file, epoch)
    local path = filepath(dir, file)
    Path.new(path):touch()
    bufnr = bufnr + 1
    buffers[bufnr] = path
    frecency:register(bufnr, epoch)
  end
  callback(register)
  vim.api.nvim_buf_get_name = original_nvim_buf_get_name
end

---@param choice "y"|"n"
---@param callback fun(called: fun(): integer): nil
---@return nil
local function with_fake_vim_ui_select(choice, callback)
  local original_vim_ui_select = vim.ui.select
  local count = 0
  local function called()
    return count
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.select = function(_, opts, on_choice)
    count = count + 1
    log.info(opts.prompt)
    log.info(opts.format_item(choice))
    on_choice(choice)
  end
  callback(called)
  vim.ui.select = original_vim_ui_select
end

describe("frecency", function()
  describe("register", function()
    describe("when opening files", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        local epoch1 = make_epoch "2023-07-29T00:00:00+09:00"
        local epoch2 = make_epoch "2023-07-29T01:00:00+09:00"
        register("hoge1.txt", epoch1)
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
          local start = os.clock()
          local results = vim.tbl_map(function(result)
            result.timestamps = nil
            return result
          end, finder:get_results(nil, make_epoch "2023-07-29T00:01:00+09:00"))
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
        end)
      end)
    end)
  end)

  describe("validate_database", function()
    describe("when no files are unlinked", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        local epoch1 = make_epoch "2023-07-29T00:00:00+09:00"
        local epoch2 = make_epoch "2023-07-29T00:01:00+09:00"
        register("hoge1.txt", epoch1)
        register("hoge2.txt", epoch2)

        it("removes no entries", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
          assert.are.same({
            { count = 1, path = filepath(dir, "hoge2.txt"), score = 10, timestamps = { epoch2 } },
            { count = 1, path = filepath(dir, "hoge1.txt"), score = 10, timestamps = { epoch1 } },
          }, results)
        end)
      end)
    end)

    describe("when with not force", function()
      describe("when files are unlinked but it is less than threshold", function()
        with_files(
          { "hoge1.txt", "hoge2.txt", "hoge3.txt", "hoge4.txt", "hoge5.txt" },
          { db_validate_threshold = 3 },
          function(frecency, finder, dir)
            local register = make_register(frecency, dir)
            local epoch1 = make_epoch "2023-07-29T00:00:00+09:00"
            local epoch2 = make_epoch "2023-07-29T00:01:00+09:00"
            local epoch3 = make_epoch "2023-07-29T00:02:00+09:00"
            local epoch4 = make_epoch "2023-07-29T00:03:00+09:00"
            local epoch5 = make_epoch "2023-07-29T00:04:00+09:00"
            register("hoge1.txt", epoch1)
            register("hoge2.txt", epoch2)
            register("hoge3.txt", epoch3)
            register("hoge4.txt", epoch4)
            register("hoge5.txt", epoch5)
            dir:joinpath("hoge1.txt"):rm()
            dir:joinpath("hoge2.txt"):rm()
            frecency:validate_database()

            it("removes no entries", function()
              local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
              table.sort(results, function(a, b)
                return a.path < b.path
              end)
              assert.are.same({
                { count = 1, path = filepath(dir, "hoge1.txt"), score = 10, timestamps = { epoch1 } },
                { count = 1, path = filepath(dir, "hoge2.txt"), score = 10, timestamps = { epoch2 } },
                { count = 1, path = filepath(dir, "hoge3.txt"), score = 10, timestamps = { epoch3 } },
                { count = 1, path = filepath(dir, "hoge4.txt"), score = 10, timestamps = { epoch4 } },
                { count = 1, path = filepath(dir, "hoge5.txt"), score = 10, timestamps = { epoch5 } },
              }, results)
            end)
          end
        )
      end)

      describe("when files are unlinked and it is more than threshold", function()
        describe('when the user response "yes"', function()
          with_files(
            { "hoge1.txt", "hoge2.txt", "hoge3.txt", "hoge4.txt", "hoge5.txt" },
            { db_validate_threshold = 3 },
            function(frecency, finder, dir)
              local register = make_register(frecency, dir)
              local epoch1 = make_epoch "2023-07-29T00:00:00+09:00"
              local epoch2 = make_epoch "2023-07-29T00:01:00+09:00"
              local epoch3 = make_epoch "2023-07-29T00:02:00+09:00"
              local epoch4 = make_epoch "2023-07-29T00:03:00+09:00"
              local epoch5 = make_epoch "2023-07-29T00:04:00+09:00"
              register("hoge1.txt", epoch1)
              register("hoge2.txt", epoch2)
              register("hoge3.txt", epoch3)
              register("hoge4.txt", epoch4)
              register("hoge5.txt", epoch5)
              dir:joinpath("hoge1.txt"):rm()
              dir:joinpath("hoge2.txt"):rm()
              dir:joinpath("hoge3.txt"):rm()

              with_fake_vim_ui_select("y", function(called)
                frecency:validate_database()

                it("called vim.ui.select()", function()
                  assert.are.same(1, called())
                end)
              end)

              it("removes entries", function()
                local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
                table.sort(results, function(a, b)
                  return a.path < b.path
                end)
                assert.are.same({
                  { count = 1, path = filepath(dir, "hoge4.txt"), score = 10, timestamps = { epoch4 } },
                  { count = 1, path = filepath(dir, "hoge5.txt"), score = 10, timestamps = { epoch5 } },
                }, results)
              end)
            end
          )
        end)

        describe('when the user response "no"', function()
          with_files(
            { "hoge1.txt", "hoge2.txt", "hoge3.txt", "hoge4.txt", "hoge5.txt" },
            { db_validate_threshold = 3 },
            function(frecency, finder, dir)
              local register = make_register(frecency, dir)
              local epoch1 = make_epoch "2023-07-29T00:00:00+09:00"
              local epoch2 = make_epoch "2023-07-29T00:01:00+09:00"
              local epoch3 = make_epoch "2023-07-29T00:02:00+09:00"
              local epoch4 = make_epoch "2023-07-29T00:03:00+09:00"
              local epoch5 = make_epoch "2023-07-29T00:04:00+09:00"
              register("hoge1.txt", epoch1)
              register("hoge2.txt", epoch2)
              register("hoge3.txt", epoch3)
              register("hoge4.txt", epoch4)
              register("hoge5.txt", epoch5)
              dir:joinpath("hoge1.txt"):rm()
              dir:joinpath("hoge2.txt"):rm()
              dir:joinpath("hoge3.txt"):rm()

              with_fake_vim_ui_select("n", function(called)
                frecency:validate_database()

                it("called vim.ui.select()", function()
                  assert.are.same(1, called())
                end)
              end)

              it("removes no entries", function()
                local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
                table.sort(results, function(a, b)
                  return a.path < b.path
                end)
                assert.are.same({
                  { count = 1, path = filepath(dir, "hoge1.txt"), score = 10, timestamps = { epoch1 } },
                  { count = 1, path = filepath(dir, "hoge2.txt"), score = 10, timestamps = { epoch2 } },
                  { count = 1, path = filepath(dir, "hoge3.txt"), score = 10, timestamps = { epoch3 } },
                  { count = 1, path = filepath(dir, "hoge4.txt"), score = 10, timestamps = { epoch4 } },
                  { count = 1, path = filepath(dir, "hoge5.txt"), score = 10, timestamps = { epoch5 } },
                }, results)
              end)
            end
          )
        end)
      end)
    end)

    describe("when with force", function()
      describe("when db_safe_mode is true", function()
        with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
          local register = make_register(frecency, dir)
          local epoch1 = make_epoch "2023-07-29T00:00:00+09:00"
          local epoch2 = make_epoch "2023-07-29T00:01:00+09:00"
          register("hoge1.txt", epoch1)
          register("hoge2.txt", epoch2)
          dir:joinpath("hoge1.txt"):rm()

          with_fake_vim_ui_select("y", function(called)
            frecency:validate_database(true)

            it("called vim.ui.select()", function()
              assert.are.same(1, called())
            end)
          end)

          it("needs confirmation for removing entries", function()
            local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
            assert.are.same({
              { count = 1, path = filepath(dir, "hoge2.txt"), score = 10, timestamps = { epoch2 } },
            }, results)
          end)
        end)
      end)

      describe("when db_safe_mode is false", function()
        with_files({ "hoge1.txt", "hoge2.txt" }, { db_safe_mode = false }, function(frecency, finder, dir)
          local register = make_register(frecency, dir)
          local epoch1 = make_epoch "2023-07-29T00:00:00+09:00"
          local epoch2 = make_epoch "2023-07-29T00:01:00+09:00"
          register("hoge1.txt", epoch1)
          register("hoge2.txt", epoch2)
          dir:joinpath("hoge1.txt"):rm()

          with_fake_vim_ui_select("y", function(called)
            frecency:validate_database(true)

            it("did not call vim.ui.select()", function()
              assert.are.same(0, called())
            end)
          end)

          it("needs no confirmation for removing entries", function()
            local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
            assert.are.same({
              { count = 1, path = filepath(dir, "hoge2.txt"), score = 10, timestamps = { epoch2 } },
            }, results)
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
          ---@diagnostic disable-next-line: duplicate-set-field
          frecency.notify = function(self, fmt, ...)
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
