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

describe("frecency", function()
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
            async.util.block_on(function()
              frecency:validate_database()
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
                async.util.block_on(function()
                  frecency:validate_database()
                end)

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
                async.util.block_on(function()
                  frecency:validate_database()
                end)

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
            async.util.block_on(function()
              frecency:validate_database(true)
            end)

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
            async.util.block_on(function()
              frecency:validate_database(true)
            end)

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

    describe("when case sensive filename", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        local epoch1 = make_epoch "2023-07-29T00:00:00+09:00"
        local epoch2 = make_epoch "2023-07-29T00:01:00+09:00"
        local epoch3 = make_epoch "2023-07-29T00:02:00+09:00"
        register("hoge1.txt", epoch1)
        register("hoge2.txt", epoch2, nil, true)
        dir:joinpath("hoge1.txt"):rm()
        dir:joinpath("hoge2.txt"):rename { new_name = dir:joinpath("_hoge2.txt").filename }
        dir:joinpath("_hoge2.txt"):rename { new_name = dir:joinpath("Hoge2.txt").filename }
        register("Hoge2.txt", epoch3)

        with_fake_vim_ui_select("y", function(called)
          async.util.block_on(function()
            frecency:validate_database(true)
          end)

          it("calls vim.ui.select()", function()
            assert.are.same(1, called())
          end)
        end)

        it("removes duplicated case sensitive filenames", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T03:00:00+09:00")
          assert.are.same({
            { count = 1, path = filepath(dir, "Hoge2.txt"), score = 10, timestamps = { epoch3 } },
          }, results)
        end)
      end)
    end)
  end)
end)
