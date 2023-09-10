---@diagnostic disable: undefined-field
local Migrator = require "frecency.migrator"
local FS = require "frecency.fs"
local Recency = require "frecency.recency"
local Sqlite = require "frecency.database.sqlite"
local Native = require "frecency.database.native"
local util = require "frecency.tests.util"
local wait = require "frecency.wait"
-- TODO: replace this with vim.system
local Job = require "plenary.job"

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

local function strptime(iso8601)
  local result = vim.fn.strptime("%FT%T%z", iso8601)
  return result ~= 0 and result or nil
end

-- NOTE: Windows has no strptime
local function time_piece(iso8601)
  local stdout, code =
    Job:new({ "perl", "-MTime::Piece", "-e", "print Time::Piece->strptime('" .. iso8601 .. "', '%FT%T%z')->epoch" })
      :sync()
  return code == 0 and tonumber(stdout[1]) or nil
end

---@param source table<string,{ count: integer, timestamps: string[] }>
local function v1_table(source)
  local records = {}
  for path, record in pairs(source) do
    local timestamps = {}
    for _, timestamp in ipairs(record.timestamps) do
      local iso8601 = timestamp .. "+0000"
      table.insert(timestamps, strptime(iso8601) or time_piece(iso8601))
    end
    records[path] = { count = record.count, timestamps = timestamps }
  end
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
            native.table,
            v1_table {
              ["hoge1.txt"] = { count = 1, timestamps = { "2023-08-21T00:00:00" } },
              ["hoge2.txt"] = { count = 1, timestamps = { "2023-08-21T00:00:00" } },
            }
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
            native.table,
            v1_table {
              ["hoge1.txt"] = { count = 4, timestamps = { "2023-08-21T00:03:00", "2023-08-21T00:04:00" } },
              ["hoge2.txt"] = { count = 3, timestamps = { "2023-08-21T00:06:00", "2023-08-21T00:07:00" } },
              ["hoge3.txt"] = { count = 2, timestamps = { "2023-08-21T00:08:00", "2023-08-21T00:09:00" } },
              ["hoge4.txt"] = { count = 1, timestamps = { "2023-08-21T00:10:00" } },
            }
          )
        end)
      end)
    end)
  end)

  describe("to_sqlite", function()
    with(function(migrator, sqlite)
      local native = Native.new(migrator.fs, { root = migrator.root })
      native.table = v1_table {
        ["hoge1.txt"] = { count = 4, timestamps = { "2023-08-21T00:03:00", "2023-08-21T00:04:00" } },
        ["hoge2.txt"] = { count = 3, timestamps = { "2023-08-21T00:06:00", "2023-08-21T00:07:00" } },
        ["hoge3.txt"] = { count = 2, timestamps = { "2023-08-21T00:08:00", "2023-08-21T00:09:00" } },
        ["hoge4.txt"] = { count = 1, timestamps = { "2023-08-21T00:10:00" } },
      }
      wait(function()
        native:save()
      end)
      migrator:to_sqlite()
      sqlite.sqlite.db:open()
      local records = sqlite.sqlite.db:eval [[
        select
          f.path,
          f.count,
          datetime(strftime('%s', t.timestamp), 'unixepoch') datetime
        from timestamps t
        join files f
          on f.id = t.file_id
        order by path, datetime
      ]]

      it("has converted into a valid DB", function()
        assert.are.same(records, {
          { path = "hoge1.txt", count = 4, datetime = "2023-08-21 00:03:00" },
          { path = "hoge1.txt", count = 4, datetime = "2023-08-21 00:04:00" },
          { path = "hoge2.txt", count = 3, datetime = "2023-08-21 00:06:00" },
          { path = "hoge2.txt", count = 3, datetime = "2023-08-21 00:07:00" },
          { path = "hoge3.txt", count = 2, datetime = "2023-08-21 00:08:00" },
          { path = "hoge3.txt", count = 2, datetime = "2023-08-21 00:09:00" },
          { path = "hoge4.txt", count = 1, datetime = "2023-08-21 00:10:00" },
        })
      end)
    end)
  end)
end)
