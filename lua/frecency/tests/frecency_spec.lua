-- HACK: This is needed because plenary.test_harness resets &rtp.
-- https://github.com/nvim-lua/plenary.nvim/blob/663246936325062427597964d81d30eaa42ab1e4/lua/plenary/test_harness.lua#L86-L86
vim.opt.runtimepath:append(vim.env.TELESCOPE_PATH)

---@diagnostic disable: invisible, undefined-field
local Frecency = require "frecency"
local Picker = require "frecency.picker"
local util = require "frecency.tests.util"
local log = require "plenary.log"
local Path = require "plenary.path"
local config = require "frecency.config"

---@param files string[]
---@param cb_or_config table|fun(frecency: Frecency, finder: FrecencyFinder, dir: PlenaryPath): nil
---@param callback? fun(frecency: Frecency, finder: FrecencyFinder, dir: PlenaryPath): nil
---@return nil
local function with_files(files, cb_or_config, callback)
  local dir, close = util.make_tree(files)
  local cfg
  if type(cb_or_config) == "table" then
    cfg = vim.tbl_extend("force", { db_root = dir.filename }, cb_or_config)
  else
    cfg = { db_root = dir.filename }
    callback = cb_or_config
  end
  assert(callback)
  log.debug(cfg)
  config.setup(cfg)
  local frecency = Frecency.new()
  frecency.picker = Picker.new(
    frecency.database,
    frecency.entry_maker,
    frecency.fs,
    frecency.recency,
    { editing_bufnr = 0, filter_delimiter = ":", show_unindexed = false, workspaces = {} }
  )
  local finder = frecency.picker:finder {}
  callback(frecency, finder, dir)
  close()
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
    local bufnr = assert(vim.fn.bufnr(path))
    if reset then
      frecency.buf_registered[bufnr] = nil
    end
    frecency:register(bufnr, datetime)
  end
end

---@param frecency Frecency
---@param dir PlenaryPath
---@param callback fun(register: fun(file: string, datetime: string?): nil): nil
---@return nil
local function with_fake_register(frecency, dir, callback)
  local bufnr = 0
  local buffers = {}
  local original_nvim_buf_get_name = vim.api.nvim_buf_get_name
  ---@diagnostic disable-next-line: redefined-local, duplicate-set-field
  vim.api.nvim_buf_get_name = function(bufnr)
    return buffers[bufnr]
  end
  local function register(file, datetime)
    local path = filepath(dir, file)
    Path.new(path):touch()
    bufnr = bufnr + 1
    buffers[bufnr] = path
    frecency:register(bufnr, datetime)
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
        register("hoge1.txt", "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", "2023-07-29T01:00:00+09:00")

        it("has valid records in DB", function()
          local results = finder:get_results(nil, "2023-07-29T02:00:00+09:00")
          assert.are.same({
            { count = 1, path = filepath(dir, "hoge2.txt"), score = 10 },
            { count = 1, path = filepath(dir, "hoge1.txt"), score = 10 },
          }, results)
        end)
      end)
    end)

    describe("when opening again", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        register("hoge1.txt", "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", "2023-07-29T01:00:00+09:00")
        register("hoge1.txt", "2023-07-29T02:00:00+09:00", true)

        it("increases the score", function()
          local results = finder:get_results(nil, "2023-07-29T03:00:00+09:00")
          assert.are.same({
            { count = 2, path = filepath(dir, "hoge1.txt"), score = 40 },
            { count = 1, path = filepath(dir, "hoge2.txt"), score = 10 },
          }, results)
        end)
      end)
    end)

    describe("when opening again but the same instance", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        register("hoge1.txt", "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", "2023-07-29T01:00:00+09:00")
        register("hoge1.txt", "2023-07-29T02:00:00+09:00")

        it("does not increase the score", function()
          local results = finder:get_results(nil, "2023-07-29T03:00:00+09:00")
          assert.are.same({
            { count = 1, path = filepath(dir, "hoge2.txt"), score = 10 },
            { count = 1, path = filepath(dir, "hoge1.txt"), score = 10 },
          }, results)
        end)
      end)
    end)

    describe("when opening more than 10 times", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        register("hoge1.txt", "2023-07-29T00:00:00+09:00")
        register("hoge1.txt", "2023-07-29T00:01:00+09:00", true)

        register("hoge2.txt", "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", "2023-07-29T00:01:00+09:00", true)
        register("hoge2.txt", "2023-07-29T00:02:00+09:00", true)
        register("hoge2.txt", "2023-07-29T00:03:00+09:00", true)
        register("hoge2.txt", "2023-07-29T00:04:00+09:00", true)
        register("hoge2.txt", "2023-07-29T00:05:00+09:00", true)
        register("hoge2.txt", "2023-07-29T00:06:00+09:00", true)
        register("hoge2.txt", "2023-07-29T00:07:00+09:00", true)
        register("hoge2.txt", "2023-07-29T00:08:00+09:00", true)
        register("hoge2.txt", "2023-07-29T00:09:00+09:00", true)
        register("hoge2.txt", "2023-07-29T00:10:00+09:00", true)
        register("hoge2.txt", "2023-07-29T00:11:00+09:00", true)

        it("calculates score from the recent 10 times", function()
          local results = finder:get_results(nil, "2023-07-29T00:12:00+09:00")
          assert.are.same({
            { count = 12, path = filepath(dir, "hoge2.txt"), score = 12 * (10 * 100) / 10 },
            { count = 2, path = filepath(dir, "hoge1.txt"), score = 2 * (2 * 100) / 10 },
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
            register(file, "2023-07-29T00:00:00+09:00")
            log.new({}, true)
          end
          local start = os.clock()
          local results = finder:get_results(nil, "2023-07-29T00:01:00+09:00")
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
        register("hoge1.txt", "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", "2023-07-29T00:01:00+09:00")

        it("removes no entries", function()
          local results = finder:get_results(nil, "2023-07-29T02:00:00+09:00")
          assert.are.same({
            { count = 1, path = filepath(dir, "hoge2.txt"), score = 10 },
            { count = 1, path = filepath(dir, "hoge1.txt"), score = 10 },
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
            register("hoge1.txt", "2023-07-29T00:00:00+09:00")
            register("hoge2.txt", "2023-07-29T00:01:00+09:00")
            register("hoge3.txt", "2023-07-29T00:02:00+09:00")
            register("hoge4.txt", "2023-07-29T00:03:00+09:00")
            register("hoge5.txt", "2023-07-29T00:04:00+09:00")
            dir:joinpath("hoge1.txt"):rm()
            dir:joinpath("hoge2.txt"):rm()
            frecency:validate_database()

            it("removes no entries", function()
              local results = finder:get_results(nil, "2023-07-29T02:00:00+09:00")
              table.sort(results, function(a, b)
                return a.path < b.path
              end)
              assert.are.same({
                { count = 1, path = filepath(dir, "hoge1.txt"), score = 10 },
                { count = 1, path = filepath(dir, "hoge2.txt"), score = 10 },
                { count = 1, path = filepath(dir, "hoge3.txt"), score = 10 },
                { count = 1, path = filepath(dir, "hoge4.txt"), score = 10 },
                { count = 1, path = filepath(dir, "hoge5.txt"), score = 10 },
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
              register("hoge1.txt", "2023-07-29T00:00:00+09:00")
              register("hoge2.txt", "2023-07-29T00:01:00+09:00")
              register("hoge3.txt", "2023-07-29T00:02:00+09:00")
              register("hoge4.txt", "2023-07-29T00:03:00+09:00")
              register("hoge5.txt", "2023-07-29T00:04:00+09:00")
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
                local results = finder:get_results(nil, "2023-07-29T02:00:00+09:00")
                table.sort(results, function(a, b)
                  return a.path < b.path
                end)
                assert.are.same({
                  { count = 1, path = filepath(dir, "hoge4.txt"), score = 10 },
                  { count = 1, path = filepath(dir, "hoge5.txt"), score = 10 },
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
              register("hoge1.txt", "2023-07-29T00:00:00+09:00")
              register("hoge2.txt", "2023-07-29T00:01:00+09:00")
              register("hoge3.txt", "2023-07-29T00:02:00+09:00")
              register("hoge4.txt", "2023-07-29T00:03:00+09:00")
              register("hoge5.txt", "2023-07-29T00:04:00+09:00")
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
                local results = finder:get_results(nil, "2023-07-29T02:00:00+09:00")
                table.sort(results, function(a, b)
                  return a.path < b.path
                end)
                assert.are.same({
                  { count = 1, path = filepath(dir, "hoge1.txt"), score = 10 },
                  { count = 1, path = filepath(dir, "hoge2.txt"), score = 10 },
                  { count = 1, path = filepath(dir, "hoge3.txt"), score = 10 },
                  { count = 1, path = filepath(dir, "hoge4.txt"), score = 10 },
                  { count = 1, path = filepath(dir, "hoge5.txt"), score = 10 },
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
          register("hoge1.txt", "2023-07-29T00:00:00+09:00")
          register("hoge2.txt", "2023-07-29T00:01:00+09:00")
          dir:joinpath("hoge1.txt"):rm()

          with_fake_vim_ui_select("y", function(called)
            frecency:validate_database(true)

            it("called vim.ui.select()", function()
              assert.are.same(1, called())
            end)
          end)

          it("needs confirmation for removing entries", function()
            local results = finder:get_results(nil, "2023-07-29T02:00:00+09:00")
            assert.are.same({
              { count = 1, path = filepath(dir, "hoge2.txt"), score = 10 },
            }, results)
          end)
        end)
      end)

      describe("when db_safe_mode is false", function()
        with_files({ "hoge1.txt", "hoge2.txt" }, { db_safe_mode = false }, function(frecency, finder, dir)
          local register = make_register(frecency, dir)
          register("hoge1.txt", "2023-07-29T00:00:00+09:00")
          register("hoge2.txt", "2023-07-29T00:01:00+09:00")
          dir:joinpath("hoge1.txt"):rm()

          with_fake_vim_ui_select("y", function(called)
            frecency:validate_database(true)

            it("did not call vim.ui.select()", function()
              assert.are.same(0, called())
            end)
          end)

          it("needs no confirmation for removing entries", function()
            local results = finder:get_results(nil, "2023-07-29T02:00:00+09:00")
            assert.are.same({
              { count = 1, path = filepath(dir, "hoge2.txt"), score = 10 },
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
        register("hoge1.txt", "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", "2023-07-29T00:01:00+09:00")

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
          local results = finder:get_results(nil, "2023-07-29T02:00:00+09:00")
          assert.are.same({
            { count = 1, path = filepath(dir, "hoge1.txt"), score = 10 },
          }, results)
        end)
      end)
    end)
  end)
end)
