local FS = require "frecency.fs"
local Native = require "frecency.database.native"
local async = require "plenary.async" --[[@as PlenaryAsync]]
local util = require "frecency.tests.util"
async.tests.add_to_env()

local function with_native(f)
  local fs = FS.new { ignore_patterns = {} }
  local dir, close = util.tmpdir()
  dir:joinpath("file_frecency.bin"):touch()
  return function()
    local native = Native.new(fs, { root = dir.filename })
    f(native)
    close()
  end
end

local function save_and_load(native, tbl, datetime)
  native:raw_save(util.v1_table(tbl))
  async.util.sleep(100)
  local entries = native:get_entries(nil, datetime)
  table.sort(entries, function(a, b)
    return a.path < b.path
  end)
  return entries
end

a.describe("frecency.database.native", function()
  a.describe("updated by another process", function()
    a.it(
      "returns valid entries",
      with_native(function(native)
        assert.are.same(
          {
            { path = "hoge1.txt", count = 1, ages = { 60 } },
            { path = "hoge2.txt", count = 1, ages = { 60 } },
          },
          save_and_load(native, {
            ["hoge1.txt"] = { count = 1, timestamps = { "2023-08-21T00:00:00+0000" } },
            ["hoge2.txt"] = { count = 1, timestamps = { "2023-08-21T00:00:00+0000" } },
          }, "2023-08-21T01:00:00+0000")
        )
      end)
    )
  end)
end)
