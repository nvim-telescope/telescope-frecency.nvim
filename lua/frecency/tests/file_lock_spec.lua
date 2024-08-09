---@diagnostic disable: undefined-field
local config = require "frecency.config"
local FileLock = require "frecency.file_lock"
local util = require "frecency.tests.util"
local async = require "plenary.async" --[[@as FrecencyPlenaryAsync]]
require("plenary.async").tests.add_to_env()

config.setup { debug = true }

local function with_dir(f)
  local dir, close = util.make_tree {}
  local filename = (dir / "file_lock_test").filename
  f(filename)
  close()
end

local function with_unlink_fails(f)
  return function()
    local original = async.uv.fs_unlink
    ---@diagnostic disable-next-line: duplicate-set-field
    async.uv.fs_unlink = function()
      return "overwritten"
    end
    f()
    async.uv.fs_unlink = original
  end
end

a.describe("file_lock", function()
  a.describe("get()", function()
    a.describe("when no lock file", function()
      with_dir(function(filename)
        local fl = FileLock.new(filename, { retry = 1, interval = 10 })
        a.it("gets successfully", function()
          assert.is.Nil(fl:get())
        end)
      end)
    end)

    a.describe("when with a lock file", function()
      with_dir(function(filename)
        local fl = FileLock.new(filename, { retry = 1, interval = 10 })
        a.it("gets successfully", function()
          local err, fd = async.uv.fs_open(fl.lock, "wx", tonumber("600", 8))
          assert.is.Nil(err)
          assert.is.Nil(async.uv.fs_close(fd))
          assert.is.Nil(fl:get())
        end)
      end)
    end)

    a.describe("when getting twice", function()
      with_dir(function(filename)
        local fl = FileLock.new(filename, { retry = 1, interval = 10 })
        a.it("gets successfully", function()
          assert.is.Nil(fl:get())
          assert.is.Nil(fl:get())
        end)
      end)
    end)

    a.describe("when getting twice but unlink fails", function()
      with_dir(function(filename)
        local fl = FileLock.new(filename, { retry = 1, interval = 10 })
        a.it(
          "fails to get",
          with_unlink_fails(function()
            assert.is.Nil(fl:get())
            assert.are.same("failed to get lock", fl:get())
          end)
        )
      end)
    end)
  end)

  a.describe("release()", function()
    a.describe("when no lock file", function()
      with_dir(function(filename)
        local fl = FileLock.new(filename, { retry = 1, interval = 10 })
        a.it("fails to release", function()
          assert.are.same("lock not found", fl:release())
        end)
      end)
    end)

    a.describe("when with a lock file", function()
      with_dir(function(filename)
        local fl = FileLock.new(filename, { retry = 1, interval = 10 })
        a.it("releases successfully", function()
          assert.is.Nil(fl:get())
          assert.is.Nil(fl:release())
        end)
      end)
    end)

    a.describe("when releasing twice", function()
      with_dir(function(filename)
        local fl = FileLock.new(filename, { retry = 1, interval = 10 })
        a.it("fails to release", function()
          assert.is.Nil(fl:get())
          assert.is.Nil(fl:release())
          assert.are.same("lock not found", fl:release())
        end)
      end)
    end)
  end)

  a.describe("with()", function()
    a.describe("when get() fails", function()
      with_dir(function(filename)
        local fl = FileLock.new(filename, { retry = 1, interval = 10 })
        a.it(
          "fails with a valid err",
          with_unlink_fails(function()
            assert.is.Nil(fl:get())
            assert.are.same(
              "failed to get lock",
              fl:with(function()
                return nil
              end)
            )
          end)
        )
      end)
    end)

    a.describe("when release() fails", function()
      with_dir(function(filename)
        local fl = FileLock.new(filename, { retry = 1, interval = 10 })
        a.it("fails with a valid err", function()
          assert.are.same(
            "lock not found",
            fl:with(function()
              assert.is.Nil(async.uv.fs_unlink(fl.lock))
              return nil
            end)
          )
        end)
      end)
    end)

    a.describe("when f() fails", function()
      with_dir(function(filename)
        local fl = FileLock.new(filename, { retry = 1, interval = 10 })
        a.it("fails with a valid err", function()
          assert.has.match(
            ": error in hoge function$",
            fl:with(function()
              error "error in hoge function"
            end)
          )
        end)
      end)
    end)

    a.describe("when no errors", function()
      with_dir(function(filename)
        local fl = FileLock.new(filename, { retry = 1, interval = 10 })
        a.it("run successfully and returns valid results", function()
          local err, result = fl:with(function()
            return "hogehogeo"
          end)
          assert.is.Nil(err)
          assert.are.same("hogehogeo", result)
        end)
      end)
    end)
  end)
end)
