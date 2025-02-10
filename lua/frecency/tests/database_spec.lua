local Database = require "frecency.database"
local config = require "frecency.config"
local async = require "plenary.async" --[[@as FrecencyPlenaryAsync]]
local util = require "frecency.tests.util"
async.tests.add_to_env()

local make_epoch = util.make_epoch

local function with_database(f)
  local dir, close = util.tmpdir()
  dir:joinpath("file_frecency.bin"):touch()
  return function()
    config.setup { debug = true, db_root = dir.filename }
    local database = Database.create "v1"
    database:start()
    f(database)
    close()
  end
end

---@async
---@param database FrecencyDatabase
---@param records table<string, table>
---@param epoch integer
---@return FrecencyEntry[]
local function save_and_load(database, records, epoch)
  ---@diagnostic disable-next-line: invisible, undefined-field
  database.tbl:set(util.v1_table(records))
  database:save()
  async.util.sleep(100)
  local entries = database:get_entries(nil, epoch)
  table.sort(entries, function(a, b)
    return a.path < b.path
  end)
  return entries
end

a.describe("frecency.database", function()
  a.describe("updated by another process", function()
    a.it(
      "returns valid entries",
      ---@param database FrecencyDatabase
      with_database(function(database)
        assert.are.same(
          {
            {
              path = "hoge1.txt",
              count = 1,
              score = 10,
              timestamps = { make_epoch "2023-08-21T00:00:00+09:00" },
            },
            {
              path = "hoge2.txt",
              count = 1,
              score = 10,
              timestamps = { make_epoch "2023-08-21T00:00:00+09:00" },
            },
          },
          save_and_load(database, {
            ["hoge1.txt"] = { count = 1, timestamps = { make_epoch "2023-08-21T00:00:00+09:00" } },
            ["hoge2.txt"] = { count = 1, timestamps = { make_epoch "2023-08-21T00:00:00+09:00" } },
          }, make_epoch "2023-08-21T01:00:00+09:00")
        )
      end)
    )
  end)
end)
