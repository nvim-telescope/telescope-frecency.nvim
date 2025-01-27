---@diagnostic disable: invisible, undefined-field
local Frecency = require "frecency.klass"
local Picker = require "frecency.picker"
local config = require "frecency.config"
local uv = vim.uv or vim.loop
local log = require "plenary.log"
local async = require "plenary.async" --[[@as FrecencyPlenaryAsync]]
local Path = require "plenary.path"
local Job = require "plenary.job"
local wait = require "frecency.wait"

---@return FrecencyPlenaryPath
---@return fun(): nil close swwp all entries
local function tmpdir()
  local ci = uv.os_getenv "CI"
  local dir
  if ci then
    dir = Path:new(assert(uv.fs_mkdtemp "tests_XXXXXX"))
  else
    local tmp = assert(uv.os_tmpdir())
    -- HACK: plenary.path resolves paths later, so here it resolves in advance.
    if uv.os_uname().sysname == "Darwin" then
      tmp = tmp:gsub("^/var", "/private/var")
    end
    dir = Path:new(assert(uv.fs_mkdtemp(Path:new(tmp, "tests_XXXXXX").filename)))
  end
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
local function v1_table(records)
  return { version = "v1", records = records }
end

---@param files string[]
---@param cb_or_config table|fun(frecency: Frecency, finder: FrecencyFinder, dir: FrecencyPlenaryPath): nil
---@param callback? fun(frecency: Frecency, finder: FrecencyFinder, dir: FrecencyPlenaryPath): nil
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
  return dir:joinpath(file):absolute()
end

---@param frecency Frecency
---@param dir FrecencyPlenaryPath
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
---@param dir FrecencyPlenaryPath
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
    Path.new(path):touch()
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

return {
  filepath = filepath,
  make_epoch = make_epoch,
  make_register = make_register,
  make_tree = make_tree,
  tmpdir = tmpdir,
  v1_table = v1_table,
  with_fake_register = with_fake_register,
  with_fake_vim_ui_select = with_fake_vim_ui_select,
  with_files = with_files,
}
