local util = require "frecency.tests.util"
local async = require "plenary.async"

local filepath = util.filepath
local make_epoch = util.make_epoch
local make_register = util.make_register
local with_fake_vim_ui_select = util.with_fake_vim_ui_select
local with_files = util.with_files

-- HACK: avoid error:
-- E5560: nvim_echo must not be called in a lua loop callback
vim.notify = function(_, _) end

---@param results FrecencyEntry[]
---@return string[]
local function paths(results)
  local out = vim
    .iter(results)
    :map(function(r)
      return r.path
    end)
    :totable()
  table.sort(out)
  return out
end

describe("frecency", function()
  describe("validate_database", function()
    describe("when no files are unlinked", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", make_epoch "2023-07-29T00:01:00+09:00")

        it("removes no entries", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
          assert.are.same({ filepath(dir, "hoge1.txt"), filepath(dir, "hoge2.txt") }, paths(results))
        end)
      end)
    end)

    describe("when force = true and db_safe_mode = false", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, { db_safe_mode = false }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", make_epoch "2023-07-29T00:01:00+09:00")
        dir:joinpath("hoge1.txt"):rm()

        with_fake_vim_ui_select("y", function(called)
          async.util.block_on(function()
            frecency:validate_database(true)
          end)

          it("removes unlinked entries without prompting", function()
            assert.are.same(0, called())
          end)
        end)

        it("keeps only the surviving entry", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
          assert.are.same({ filepath(dir, "hoge2.txt") }, paths(results))
        end)
      end)
    end)

    describe("case sensitive filename collision", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", make_epoch "2023-07-29T00:01:00+09:00", nil, true)
        dir:joinpath("hoge1.txt"):rm()
        dir:joinpath("hoge2.txt"):rename { new_name = dir:joinpath("_hoge2.txt").filename }
        dir:joinpath("_hoge2.txt"):rename { new_name = dir:joinpath("Hoge2.txt").filename }
        register("Hoge2.txt", make_epoch "2023-07-29T00:02:00+09:00")

        with_fake_vim_ui_select("y", function(_)
          async.util.block_on(function()
            frecency:validate_database(true)
          end)
        end)

        it("dedupes case-different paths to the surviving one", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T03:00:00+09:00")
          assert.are.same({ filepath(dir, "Hoge2.txt") }, paths(results))
        end)
      end)
    end)
  end)

  -- vim.ui.select() replacements such as telescope's ui_select() return
  -- before the choice is made. start() should open the picker only after it,
  -- since opening the picker would close the one for the confirmation.
  describe("start with unlinked entries and vim.ui.select() returning at once", function()
    ---@param choice "y"|nil
    ---@param callback fun(events: string[], finder: FrecencyFinder, dir: FrecencyPlenaryPath): nil
    local function with_deferred_choice(choice, callback)
      with_files({ "hoge1.txt", "hoge2.txt" }, { db_validate_threshold = 1 }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", make_epoch "2023-07-29T00:01:00+09:00")
        dir:joinpath("hoge1.txt"):rm()

        local events = {}
        local Picker = require "frecency.picker"
        local original_new = Picker.new
        local original_select = vim.ui.select
        ---@diagnostic disable-next-line: duplicate-set-field
        Picker.new = function()
          return {
            start = function()
              table.insert(events, "picker")
            end,
          }
        end
        local on_choice
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.ui.select = function(_, _, f)
          table.insert(events, "select")
          on_choice = f
        end

        frecency:setup(false, true)
        frecency:start()
        table.insert(events, "returned")
        on_choice(choice)
        vim.wait(1000, function()
          return events[#events] == "picker"
        end)

        Picker.new = original_new
        vim.ui.select = original_select
        callback(events, finder, dir)
      end)
    end

    describe("when the removal is confirmed", function()
      with_deferred_choice("y", function(events, finder, dir)
        it("opens the picker after the choice", function()
          assert.are.same({ "select", "returned", "picker" }, events)
        end)

        it("removes unlinked entries", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
          assert.are.same({ filepath(dir, "hoge2.txt") }, paths(results))
        end)
      end)
    end)

    describe("when the removal is aborted", function()
      with_deferred_choice(nil, function(events, finder, dir)
        it("opens the picker after the choice", function()
          assert.are.same({ "select", "returned", "picker" }, events)
        end)

        it("keeps all entries", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
          assert.are.same({ filepath(dir, "hoge1.txt"), filepath(dir, "hoge2.txt") }, paths(results))
        end)
      end)
    end)
  end)
end)
