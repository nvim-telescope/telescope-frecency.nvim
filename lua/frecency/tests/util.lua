local uv = vim.uv or vim.loop
local async = require "plenary.async" --[[@as FrecencyPlenaryAsync]]
local Path = require "plenary.path"
local Job = require "plenary.job"
local wait = require "frecency.tests.wait"

---@return FrecencyPlenaryPath
---@return fun(): nil close swwp all entries
local function tmpdir()
  local dir = Path:new(Path:new(assert(uv.fs_mkdtemp "tests_XXXXXX")):absolute())
  return dir, function()
    dir:rm { recursive = true }
  end
end

---@param entries string[]
---@return FrecencyPlenaryPath dir the top dir of tree
---@return fun(): nil close sweep all entries
local function make_tree(entries)
  local dir, close = tmpdir()
  for _, entry in ipairs(entries) do
    ---@diagnostic disable-next-line: undefined-field
    dir:joinpath(entry):touch { parents = true }
  end
  return dir, close
end

local AsyncJob = async.wrap(function(cmd, callback)
  return Job:new({
    command = cmd[1],
    args = { select(2, unpack(cmd)) },
    on_exit = function(self, code, _)
      local stdout = code == 0 and table.concat(self:result(), "\n") or nil
      callback(stdout, code)
    end,
  }):start()
end, 2)

-- NOTE: vim.fn.strptime cannot be used in Lua loop
local function time_piece(iso8601)
  local epoch
  wait(function()
    local stdout, code =
      AsyncJob { "perl", "-MTime::Piece", "-e", "print Time::Piece->strptime('" .. iso8601 .. "', '%FT%T%z')->epoch" }
    epoch = code == 0 and tonumber(stdout) or nil
  end)
  return epoch
end

---@param records table<string, FrecencyDatabaseRecordValue>
local function v1_table(records)
  return { version = "v1", records = records }
end

return { make_tree = make_tree, tmpdir = tmpdir, v1_table = v1_table, time_piece = time_piece }
