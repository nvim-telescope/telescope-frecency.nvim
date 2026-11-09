---@diagnostic disable: invisible, undefined-field
-- luacheck: globals describe it pending before_each after_each
local Frecency = require "frecency.klass"
local Picker = require "frecency.picker"
local config = require "frecency.config"
local os_util = require "frecency.os_util"
local log = require "frecency.log"
local async = require "neoplen.async" --[[@as FrecencyPlenaryAsync]]
local wait = require "frecency.wait"

-- Minimal replacement for the parts of plenary.path that the specs use.
---@class FrecencyTestPath
---@field filename string
local TestPath = {}
TestPath.__index = TestPath

---@param filename string
---@return FrecencyTestPath
function TestPath.new(filename)
  return setmetatable({ filename = filename }, TestPath)
end

---@param ... string
---@return FrecencyTestPath
function TestPath:joinpath(...)
  return TestPath.new(vim.fs.joinpath(self.filename, ...))
end

TestPath.__div = TestPath.joinpath

---@return string
function TestPath:absolute()
  return vim.fs.abspath(self.filename)
end

---@param opts? { parents: boolean? }
---@return nil
function TestPath:touch(opts)
  if opts and opts.parents then
    vim.fn.mkdir(vim.fs.dirname(self.filename), "p")
  end
  local fd = assert(vim.uv.fs_open(self.filename, "a", tonumber("644", 8)))
  assert(vim.uv.fs_close(fd))
end

---@param opts? { recursive: boolean? }
---@return nil
function TestPath:rm(opts)
  vim.fs.rm(self.filename, { recursive = opts and opts.recursive })
end

---@param opts { new_name: string }
---@return nil
function TestPath:rename(opts)
  assert(vim.uv.fs_rename(self.filename, opts.new_name))
end

---@return FrecencyTestPath
---@return fun(): nil close sweep all entries
local function tmpdir()
  local ci = vim.uv.os_getenv "CI"
  local template = ci and "tests_XXXXXX" or vim.fs.joinpath(assert(vim.uv.os_tmpdir()), "tests_XXXXXX")
  -- NOTE: Resolve symlinks (e.g. /var -> /private/var on macOS) in advance so
  -- that paths match the ones Neovim reports for buffers.
  local dir = TestPath.new(os_util.normalize(assert(vim.uv.fs_realpath(assert(vim.uv.fs_mkdtemp(template))))))
  return dir, function()
    dir:rm { recursive = true }
  end
end

---@param entries string[]
---@return FrecencyTestPath dir the top dir of tree
---@return fun(): nil close sweep all entries
local function make_tree(entries)
  local dir, close = tmpdir()
  for _, entry in ipairs(entries) do
    dir:joinpath(entry):touch { parents = true }
  end
  return dir, close
end

local AsyncJob = async.wrap(function(cmd, callback)
  vim.system(cmd, { text = true }, function(obj)
    callback(obj.code == 0 and vim.trim(obj.stdout) or nil, obj.code)
  end)
end, 2)

-- NOTE: vim.fn.strptime cannot be used in Lua loop
---@param iso8601 string
---@return integer?
local function time_piece(iso8601)
  local epoch
  wait(function()
    local stdout, code =
      AsyncJob { "perl", "-MTime::Piece", "-e", "print Time::Piece->strptime('" .. iso8601 .. "', '%FT%T%z')->epoch" }
    epoch = code == 0 and tonumber(stdout) or nil
  end)
  return epoch
end

---@param datetime string?
---@return integer
local function make_epoch(datetime)
  if not datetime then
    return os.time()
  end
  local tz_fix = datetime:gsub("+(%d%d):(%d%d)$", "+%1%2")
  return time_piece(tz_fix) or 0
end

---@param records table<string, table>
---@param reference_time? integer default: os.time()
---@param half_life? integer default: 3 days
local function v2_table(records, reference_time, half_life)
  return {
    version = "v2",
    reference_time = reference_time or os.time(),
    half_life = half_life or 60 * 60 * 24 * 3,
    records = records,
  }
end

---@param files string[]
---@param cb_or_config table|fun(frecency: Frecency, finder: FrecencyFinder, dir: FrecencyTestPath): nil
---@param callback? fun(frecency: Frecency, finder: FrecencyFinder, dir: FrecencyTestPath): nil
---@return nil
local function with_files(files, cb_or_config, callback)
  local dir, close = make_tree(files)
  local cfg
  if type(cb_or_config) == "table" then
    cfg = vim.tbl_extend("force", { debug = true, db_root = dir.filename }, cb_or_config)
  else
    cfg = { debug = true, db_root = dir.filename }
    callback = cb_or_config
  end
  assert(callback)
  log.debug(cfg)
  config.setup(cfg)
  local frecency = Frecency.new()
  async.util.block_on(function()
    frecency.database:start()
    frecency.database.tbl:wait_ready()
  end)
  frecency.picker = Picker.new(frecency.database, { editing_bufnr = 0 })
  local finder = frecency.picker:finder {}
  callback(frecency, finder, dir)
  close()
end

local function filepath(dir, file)
  return os_util.normalize(dir:joinpath(file):absolute())
end

---@param frecency Frecency
---@param dir FrecencyTestPath
---@return fun(file: string, epoch: integer, reset: boolean?, wipeout?: boolean): nil reset: boolean?): nil
local function make_register(frecency, dir)
  return function(file, epoch, reset, wipeout)
    -- NOTE: this function does the same thing as BufWinEnter autocmd.
    ---@param bufnr integer
    local function register(bufnr)
      if vim.api.nvim_buf_get_name(bufnr) == "" then
        return
      end
      local is_floatwin = vim.api.nvim_win_get_config(0).relative ~= ""
      if is_floatwin or (config.ignore_register and config.ignore_register(bufnr)) then
        return
      end
      async.util.block_on(function()
        frecency:register(bufnr, vim.api.nvim_buf_get_name(bufnr), epoch)
      end)
    end

    local path = filepath(dir, file)
    vim.cmd.edit(path)
    local bufnr = assert(vim.fn.bufnr(path))
    if reset then
      frecency.buf_registered[bufnr] = nil
    end
    register(bufnr)
    -- HACK: This is needed because almost the same filenames use the same
    -- buffer.
    if wipeout then
      vim.cmd.bwipeout()
    end
  end
end

---@param frecency Frecency
---@param dir FrecencyTestPath
---@param callback fun(register: fun(file: string, epoch?: integer): nil): nil
---@return nil
local function with_fake_register(frecency, dir, callback)
  local bufnr = 0
  local buffers = {}
  local original_nvim_buf_get_name = vim.api.nvim_buf_get_name
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_buf_get_name = function(buf)
    return buffers[buf]
  end
  ---@param file string
  ---@param epoch integer
  local function register(file, epoch)
    local path = filepath(dir, file)
    TestPath.new(path):touch()
    bufnr = bufnr + 1
    buffers[bufnr] = path
    async.util.block_on(function()
      frecency:register(bufnr, path, epoch)
    end)
  end
  callback(register)
  vim.api.nvim_buf_get_name = original_nvim_buf_get_name
end

---@param choice "y"|"n"
---@param callback fun(called: fun(): integer): nil
---@return nil
local function with_fake_vim_ui_select(choice, callback)
  local original_vim_ui_select = vim.ui.select
  local count = 0
  local function called()
    return count
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.select = function(_, opts, on_choice)
    count = count + 1
    log.info(opts.prompt)
    log.info(opts.format_item(choice))
    on_choice(choice)
  end
  callback(called)
  vim.ui.select = original_vim_ui_select
end

-- Replacement for `require("plenary.async").tests.add_to_env()`: neoplen
-- removed the `async.tests` submodule, so we inline the minimal helpers that
-- frecency's spec files use (`a.describe` / `a.it` / `a.before_each` /
-- `a.after_each` / `a.pending`). Sets `_G.a` so call sites resolve through the
-- global table the same way `setfenv`-based add_to_env did.
local function add_async_to_env()
  local timeout = tonumber(vim.env.PLENTEST_TIMEOUT)
  _G.a = {
    describe = describe,
    it = function(s, async_func)
      it(s, async.util.will_block(async_func, timeout))
    end,
    pending = function(async_func)
      pending(async_func)
    end,
    before_each = function(async_func)
      before_each(async.util.will_block(async_func))
    end,
    after_each = function(async_func)
      after_each(async.util.will_block(async_func))
    end,
  }
end

return {
  add_async_to_env = add_async_to_env,
  filepath = filepath,
  make_epoch = make_epoch,
  make_register = make_register,
  make_tree = make_tree,
  tmpdir = tmpdir,
  v2_table = v2_table,
  with_fake_register = with_fake_register,
  with_fake_vim_ui_select = with_fake_vim_ui_select,
  with_files = with_files,
}
