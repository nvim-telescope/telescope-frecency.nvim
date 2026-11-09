local Database = require "frecency.database"
local config = require "frecency.config"
local os_util = require "frecency.os_util"
local async = require "neoplen.async" --[[@as FrecencyPlenaryAsync]]
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

-- Like with_loading_database(), but the database is loaded with a normalizer
-- that treats "\\" as a path separator, as os_util.normalize() does on
-- Windows. The callback receives a function to load the file again.
local function with_backslash_database(records, f)
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

    local original = os_util.normalize
    os_util.normalize = function(path)
      return (path:gsub("\\", "/"))
    end
    local database = Database.create()
    database:start()
    ---@diagnostic disable-next-line: invisible, undefined-field
    database.tbl:wait_ready()
    -- Let the save triggered by the migration finish.
    async.util.sleep(100)
    os_util.normalize = original
    f(database, function()
      local reloaded = Database.create()
      reloaded:start()
      ---@diagnostic disable-next-line: invisible, undefined-field
      reloaded.tbl:wait_ready()
      return reloaded
    end)
    close()
  end
end

---@param database FrecencyDatabase
---@return table<string, FrecencyDatabaseEntry>
local function entries_by_path(database)
  return vim.iter(database:get_entries()):fold({}, function(a, entry)
    a[entry.path] = entry
    return a
  end)
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
        async.util.sleep(100)
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

  a.describe("when the file on disk has paths with backslashes", function()
    a.it(
      "rewrites them with slashes and saves the result",
      with_backslash_database({
        ["dir\\hoge1.txt"] = { score = 1, last_accessed = 0, num_accesses = 1 },
        ["dir/hoge2.txt"] = { score = 2, last_accessed = 0, num_accesses = 2 },
      }, function(database, reload)
        local expected = { "dir/hoge1.txt", "dir/hoge2.txt" }
        local paths = vim.tbl_keys(entries_by_path(database))
        table.sort(paths)
        assert.are.same(expected, paths)
        paths = vim.tbl_keys(entries_by_path(reload()))
        table.sort(paths)
        assert.are.same(expected, paths)
      end)
    )

    a.it(
      "merges records that point to the same file",
      with_backslash_database({
        ["dir\\hoge.txt"] = { score = 1, last_accessed = 10, num_accesses = 1 },
        ["dir/hoge.txt"] = { score = 2, last_accessed = 20, num_accesses = 3 },
      }, function(database)
        local by_path = entries_by_path(database)
        assert.are.same({ "dir/hoge.txt" }, vim.tbl_keys(by_path))
        assert.are.same(4, by_path["dir/hoge.txt"].num_accesses)
        ---@diagnostic disable-next-line: invisible, undefined-field
        local record = database.tbl:get_record "dir/hoge.txt"
        assert.are.same({ score = 3, last_accessed = 20, num_accesses = 4 }, record)
      end)
    )
  end)
end)
