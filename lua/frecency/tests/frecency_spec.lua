-- HACK: This is needed because plenary.test_harness resets &rtp.
-- luacheck: push no max comment line length
-- https://github.com/nvim-lua/plenary.nvim/blob/663246936325062427597964d81d30eaa42ab1e4/lua/plenary/test_harness.lua#L86-L86
-- luacheck: pop
vim.opt.runtimepath:append(vim.env.TELESCOPE_PATH)

local util = require "frecency.tests.util"

local filepath = util.filepath
local make_epoch = util.make_epoch
local make_register = util.make_register
local with_files = util.with_files

---@param results FrecencyEntry[]
---@return string[]
local function paths(results)
  return vim
    .iter(results)
    :map(function(r)
      return r.path
    end)
    :totable()
end

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

        it("returns both files with the more recent one first", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
          assert.are.same({ filepath(dir, "hoge2.txt"), filepath(dir, "hoge1.txt") }, paths(results))
        end)
      end)
    end)

    describe("when opening the same file again across instances", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", make_epoch "2023-07-29T01:00:00+09:00")
        register("hoge1.txt", make_epoch "2023-07-29T02:00:00+09:00", true)

        it("bumps the re-registered file ahead", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T03:00:00+09:00")
          assert.are.same({ filepath(dir, "hoge1.txt"), filepath(dir, "hoge2.txt") }, paths(results))
        end)

        it("increments num_accesses for the re-registered file", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T03:00:00+09:00")
          local by_path = {}
          for _, r in ipairs(results) do
            by_path[r.path] = r
          end
          assert.are.same(2, by_path[filepath(dir, "hoge1.txt")].num_accesses)
          assert.are.same(1, by_path[filepath(dir, "hoge2.txt")].num_accesses)
        end)
      end)
    end)

    describe("when re-registering within the same instance", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", make_epoch "2023-07-29T01:00:00+09:00")
        register("hoge1.txt", make_epoch "2023-07-29T02:00:00+09:00")

        it("does not double-count the same buffer registration", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T03:00:00+09:00")
          local by_path = {}
          for _, r in ipairs(results) do
            by_path[r.path] = r
          end
          assert.are.same(1, by_path[filepath(dir, "hoge1.txt")].num_accesses)
          assert.are.same(1, by_path[filepath(dir, "hoge2.txt")].num_accesses)
        end)
      end)
    end)

    describe("when ignore_register is set", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, {
        ignore_register = function(bufnr)
          local _, bufname = pcall(vim.api.nvim_buf_get_name, bufnr)
          return not not (bufname and bufname:find "hoge2%.txt$")
        end,
      }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", make_epoch "2023-07-29T01:00:00+09:00")
        it("filters out files where ignore_register returns true", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
          assert.are.same({ filepath(dir, "hoge1.txt") }, paths(results))
        end)
      end)
    end)
  end)

  describe("delete", function()
    describe("when file exists", function()
      with_files({ "hoge1.txt", "hoge2.txt" }, function(frecency, finder, dir)
        local register = make_register(frecency, dir)
        register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
        register("hoge2.txt", make_epoch "2023-07-29T00:01:00+09:00")

        it("notifies on successful deletion", function()
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

        it("removes only the deleted entry", function()
          local results = finder:get_results(nil, make_epoch "2023-07-29T02:00:00+09:00")
          assert.are.same({ filepath(dir, "hoge1.txt") }, paths(results))
        end)
      end)
    end)
  end)

  describe("query", function()
    with_files({ "hoge1.txt", "hoge2.txt", "hoge3.txt", "hoge4.txt" }, function(frecency, _, dir)
      local register = make_register(frecency, dir)
      register("hoge1.txt", make_epoch "2023-07-29T00:00:00+09:00")
      register("hoge2.txt", make_epoch "2023-07-29T00:01:00+09:00")
      register("hoge1.txt", make_epoch "2023-07-29T00:02:00+09:00", true)
      register("hoge3.txt", make_epoch "2023-07-29T00:03:00+09:00")
      register("hoge1.txt", make_epoch "2023-07-29T00:04:00+09:00", true)
      register("hoge3.txt", make_epoch "2023-07-29T00:05:00+09:00", true)
      register("hoge4.txt", make_epoch "2023-07-29T00:06:00+09:00")

      describe("with no opts", function()
        it("returns paths sorted by score descending", function()
          local results = frecency:query(nil, make_epoch "2023-07-29T04:00:00+09:00")
          -- hoge1 has 3 accesses, hoge3 has 2; among the 1-access entries
          -- hoge4 was accessed last (T00:06) so its v2 decay leaves it
          -- slightly higher than hoge2 (T00:01).
          assert.are.same({
            filepath(dir, "hoge1.txt"),
            filepath(dir, "hoge3.txt"),
            filepath(dir, "hoge4.txt"),
            filepath(dir, "hoge2.txt"),
          }, results)
        end)
      end)

      describe("with limit", function()
        it("truncates to the requested limit", function()
          assert.are.same(3, #frecency:query({ limit = 3 }, make_epoch "2023-07-29T04:00:00+09:00"))
        end)
      end)

      describe("with order = path", function()
        it("sorts ascending by path when direction = asc", function()
          local results = frecency:query({ direction = "asc", order = "path" }, make_epoch "2023-07-29T04:00:00+09:00")
          assert.are.same({
            filepath(dir, "hoge1.txt"),
            filepath(dir, "hoge2.txt"),
            filepath(dir, "hoge3.txt"),
            filepath(dir, "hoge4.txt"),
          }, results)
        end)
      end)

      describe("with record = true", function()
        local results = frecency:query(
          { direction = "asc", limit = 3, order = "path", record = true },
          make_epoch "2023-07-29T04:00:00+09:00"
        )

        it("returns objects in the requested order", function()
          assert.are.same(
            {
              filepath(dir, "hoge1.txt"),
              filepath(dir, "hoge2.txt"),
              filepath(dir, "hoge3.txt"),
            },
            vim
              .iter(results)
              :map(function(r)
                return r.path
              end)
              :totable()
          )
        end)

        it("exposes v2 fields plus the count alias", function()
          local first = results[1]
          assert.are.same(filepath(dir, "hoge1.txt"), first.path)
          assert.are.same(3, first.num_accesses)
          assert.are.same(3, first.count)
          assert.is_number(first.score)
          assert.is_number(first.last_accessed)
          assert.is_number(first.half_life)
          assert.is_number(first.reference_time)
        end)
      end)

      describe("with order = count", function()
        it("sorts by num_accesses descending", function()
          local results = frecency:query({ order = "count", record = true }, make_epoch "2023-07-29T04:00:00+09:00")
          assert.are.same(
            { 3, 2, 1, 1 },
            vim
              .iter(results)
              :map(function(r)
                return r.num_accesses
              end)
              :totable()
          )
        end)
      end)

      describe("with order = timestamps", function()
        it("sorts by last_accessed descending", function()
          local results = frecency:query({ order = "timestamps" }, make_epoch "2023-07-29T04:00:00+09:00")
          assert.are.same({
            filepath(dir, "hoge4.txt"),
            filepath(dir, "hoge3.txt"),
            filepath(dir, "hoge1.txt"),
            filepath(dir, "hoge2.txt"),
          }, results)
        end)
      end)
    end)
  end)
end)
