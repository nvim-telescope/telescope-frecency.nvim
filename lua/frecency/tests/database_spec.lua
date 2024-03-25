local FS = require "frecency.fs"
local Database = require "frecency.database"
local config = require "frecency.config"
local async = require "plenary.async" --[[@as FrecencyPlenaryAsync]]
local util = require "frecency.tests.util"
async.tests.add_to_env()

local function with_database(f)
  local fs = FS.new { ignore_patterns = {} }
  local dir, close = util.tmpdir()
  dir:joinpath("file_frecency.bin"):touch()
  return function()
    config.setup { db_root = dir.filename }
    local database = Database.new(fs)
    f(database)
    close()
  end
end

local function save_and_load(database, tbl, datetime)
  database:raw_save(util.v1_table(tbl))
  async.util.sleep(100)
  local entries = database:get_entries(nil, datetime)
  table.sort(entries, function(a, b)
    return a.path < b.path
  end)
  return entries
end

a.describe("frecency.database", function()
  a.describe("updated by another process", function()
    a.it(
      "returns valid entries",
      with_database(function(database)
        assert.are.same(
          {
            { path = "hoge1.txt", count = 1, ages = { 60 } },
            { path = "hoge2.txt", count = 1, ages = { 60 } },
          },
          save_and_load(database, {
            ["hoge1.txt"] = { count = 1, timestamps = { "2023-08-21T00:00:00+0000" } },
            ["hoge2.txt"] = { count = 1, timestamps = { "2023-08-21T00:00:00+0000" } },
          }, "2023-08-21T01:00:00+0000")
        )
      end)
    )
  end)
end)
