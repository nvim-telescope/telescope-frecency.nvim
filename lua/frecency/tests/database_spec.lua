local FS = require "frecency.fs"
local Database = require "frecency.database"
local config = require "frecency.config"
local async = require "plenary.async" --[[@as FrecencyPlenaryAsync]]
local util = require "frecency.tests.util"
async.tests.add_to_env()

---@param datetime string?
---@return integer
local function make_epoch(datetime)
  if not datetime then
    return os.time()
  end
  local tz_fix = datetime:gsub("+(%d%d):(%d%d)$", "+%1%2")
  return util.time_piece(tz_fix)
end

local function with_database(f)
  local fs = FS.new { ignore_patterns = {} }
  local dir, close = util.tmpdir()
  dir:joinpath("file_frecency.bin"):touch()
  return function()
    config.setup { debug = true, db_root = dir.filename }
    local database = Database.new(fs)
    f(database)
    close()
  end
end

---@async
---@param database FrecencyDatabase
---@param tbl table<string, FrecencyDatabaseRecordValue>
---@param epoch integer
---@return FrecencyEntry[]
local function save_and_load(database, tbl, epoch)
  database:raw_save(util.v1_table(tbl))
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
              ages = { 60 },
              timestamps = { make_epoch "2023-08-21T00:00:00+09:00" },
            },
            {
              path = "hoge2.txt",
              count = 1,
              ages = { 60 },
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
