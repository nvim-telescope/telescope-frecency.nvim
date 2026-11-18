local Database = require "frecency.database"
local config = require "frecency.config"
local async = require "frecency.async"
local util = require "frecency.tests.util"
util.add_async_to_env()

local function with_database(f)
  local dir, close = util.tmpdir()
  -- Touch a v2 file so DatabaseV2:filename() skips the migration probe.
  dir:joinpath("file_frecency_v2.bin"):touch()
  return function()
    config.setup { debug = true, db_root = dir.filename }
    local database = Database.create()
    database:start()
    -- Let the initial load coroutine settle before we mutate the table.
    ---@diagnostic disable-next-line: invisible, undefined-field
    database.tbl:wait_ready()
    f(database)
    close()
  end
end

-- Like with_database(), but the file on disk already holds a record and the
-- callback runs without waiting for the initial load.
local function with_loading_database(records, f)
  local dir, close = util.tmpdir()
  return function()
    config.setup { debug = true, db_root = dir.filename }
    local seed = Database.create()
    seed:start()
    ---@diagnostic disable-next-line: invisible, undefined-field
    seed.tbl:wait_ready()
    ---@diagnostic disable-next-line: invisible, undefined-field
    seed.tbl:set(util.v2_table(records))
    seed:save()

    local database = Database.create()
    database:start()
    f(database)
    close()
  end
end

a.describe("frecency.database", function()
  a.describe("when a record is written while the initial load is in flight", function()
    a.it(
      "keeps both the loaded records and the new one",
      with_loading_database({ ["hoge1.txt"] = { score = 1, last_accessed = 0, num_accesses = 1 } }, function(database)
        database:update "hoge2.txt"
        local paths = vim
          .iter(database:get_entries())
          :map(function(entry)
            return entry.path
          end)
          :totable()
        table.sort(paths)
        assert.are.same({ "hoge1.txt", "hoge2.txt" }, paths)
      end)
    )
  end)

  a.describe("v2 round-trip", function()
    a.it(
      "preserves records across save -> get_entries",
      with_database(function(database)
        local ref = os.time()
        local now = ref + 60
        ---@diagnostic disable-next-line: invisible, undefined-field
        database.tbl:set(util.v2_table({
          ["hoge1.txt"] = { score = 1, last_accessed = 0, num_accesses = 1 },
          ["hoge2.txt"] = { score = 2, last_accessed = 30, num_accesses = 3 },
        }, ref))
        database:save()
        async.sleep(100)
        local entries = database:get_entries(nil, now)
        table.sort(entries, function(a, b)
          return a.path < b.path
        end)
        assert.are.same(2, #entries)
        assert.are.same("hoge1.txt", entries[1].path)
        assert.are.same(1, entries[1].num_accesses)
        assert.are.same("hoge2.txt", entries[2].path)
        assert.are.same(3, entries[2].num_accesses)
      end)
    )
  end)
end)
