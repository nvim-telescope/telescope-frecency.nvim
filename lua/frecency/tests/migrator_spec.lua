local Migrator = require "frecency.migrator"
local FS = require "frecency.fs"
local Recency = require "frecency.recency"
local Sqlite = require "frecency.database.sqlite"
local Native = require "frecency.database.native"
local util = require "frecency.tests.util"
local log = require "plenary.log"

---@param callback fun(migrator: FrecencyMigrator, sqlite: FrecencyDatabase): nil
---@return nil
local function with(callback)
  local dir, close = util.tmpdir()
  local recency = Recency.new { max_count = 2 }
  local fs = FS.new { ignore_patterns = {} }
  local migrator = Migrator.new(fs, recency, dir.filename)
  local sqlite = Sqlite.new(fs, { root = dir.filename })
  callback(migrator, sqlite)
  close()
end

---@param source table<string,{ count: integer, timestamps: string[] }>
local function make_table(source)
  local records = {}
  for path, record in pairs(source) do
    local timestamps = {}
    for _, timestamp in ipairs(record.timestamps) do
      table.insert(timestamps, vim.fn.strptime("%FT%T%z", timestamp))
    end
    records[path] = { count = record.count, timestamps = timestamps }
  end
  log.debug { make_table = records }
  return { version = "v1", records = records }
end

describe("migrator", function()
  describe("to_v1", function()
    describe("when with simple database", function()
      with(function(migrator, sqlite)
        for _, path in ipairs { "hoge1.txt", "hoge2.txt" } do
          sqlite:update(path, migrator.recency.config.max_count, "2023-08-21T00:00:00")
        end
        migrator:to_v1()
        local native = Native.new(migrator.fs, { root = migrator.root })

        it("has converted into a valid table", function()
          assert.are.same(
            make_table {
              ["hoge1.txt"] = { count = 1, timestamps = { "2023-08-21T00:00:00+0000" } },
              ["hoge2.txt"] = { count = 1, timestamps = { "2023-08-21T00:00:00+0000" } },
            },
            native.table
          )
        end)
      end)
    end)

    describe("when with more large database", function()
      with(function(migrator, sqlite)
        for i, path in ipairs {
          "hoge1.txt",
          "hoge1.txt",
          "hoge1.txt",
          "hoge1.txt",
          "hoge2.txt",
          "hoge2.txt",
          "hoge2.txt",
          "hoge3.txt",
          "hoge3.txt",
          "hoge4.txt",
        } do
          sqlite:update(path, migrator.recency.config.max_count, ("2023-08-21T00:%02d:00"):format(i))
        end
        migrator:to_v1()
        local native = Native.new(migrator.fs, { root = migrator.root })

        it("has converted into a valid table", function()
          assert.are.same(
            make_table {
              ["hoge1.txt"] = { count = 4, timestamps = { "2023-08-21T00:03:00+0000", "2023-08-21T00:04:00+0000" } },
              ["hoge2.txt"] = { count = 3, timestamps = { "2023-08-21T00:06:00+0000", "2023-08-21T00:07:00+0000" } },
              ["hoge3.txt"] = { count = 2, timestamps = { "2023-08-21T00:08:00+0000", "2023-08-21T00:09:00+0000" } },
              ["hoge4.txt"] = { count = 1, timestamps = { "2023-08-21T00:10:00+0000" } },
            },
            native.table
          )
        end)
      end)
    end)
  end)
end)
