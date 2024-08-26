---@type FrecencyDatabase?
local database

---This object is intended to be used as a singleton, and is lazily loaded.
---When methods are called at the first time, it calls the constructor and
---setup() to be initialized.
---@class FrecencyInstance
---@field bootstrap async fun(): nil
---@field complete fun(findstart: 1|0, base: string): integer|''|string[]
---@field delete async fun(path: string): nil
---@field query fun(opts?: FrecencyQueryOpts): FrecencyQueryEntry[]|string[]
---@field register async fun(bufnr: integer, datetime: string?): nil
---@field start fun(opts: FrecencyPickerOptions?): nil
---@field validate_database async fun(force: boolean?): nil
local frecency = setmetatable({}, {
  ---@param self FrecencyInstance
  ---@param key "complete"|"delete"|"register"|"start"|"validate_database"
  ---@return function
  __index = function(self, key)
    ---@return Frecency
    local function instance()
      return rawget(self, "instance")
    end

    return function(...)
      if not instance() then
        rawset(self, "instance", require("frecency.klass").new(database))
        instance():setup()
      end
      return instance()[key](instance(), ...)
    end
  end,
})

local function async_call(f, ...)
  require("plenary.async").void(f)(...)
end

local setup_done = false

---When this func is called, Frecency instance is NOT created but only
---configuration is done.
---@param ext_config? FrecencyOpts
---@return nil
local function setup(ext_config)
  if setup_done then
    return
  end

  local config = require "frecency.config"
  config.setup(ext_config)
  local timer = require "frecency.timer"
  timer.track "setup() start"

  vim.api.nvim_set_hl(0, "TelescopeBufferLoaded", { link = "String", default = true })
  vim.api.nvim_set_hl(0, "TelescopePathSeparator", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "TelescopeFrecencyScores", { link = "Number", default = true })
  vim.api.nvim_set_hl(0, "TelescopeQueryFilter", { link = "WildMenu", default = true })

  ---@class FrecencyCommandInfo
  ---@field args string
  ---@field bang boolean

  ---@param cmd_info FrecencyCommandInfo
  vim.api.nvim_create_user_command("FrecencyValidate", function(cmd_info)
    async_call(frecency.validate_database, cmd_info.bang)
  end, { bang = true, desc = "Clean up DB for telescope-frecency" })

  ---@param cmd_info FrecencyCommandInfo
  vim.api.nvim_create_user_command("FrecencyDelete", function(cmd_info)
    local path_string = cmd_info.args == "" and "%:p" or cmd_info.args
    local path = vim.fn.expand(path_string) --[[@as string]]
    async_call(frecency.delete, path)
  end, { nargs = "?", complete = "file", desc = "Delete entry from telescope-frecency" })

  local group = vim.api.nvim_create_augroup("TelescopeFrecency", {})
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWritePost" }, {
    desc = "Update database for telescope-frecency",
    group = group,
    ---@param args { buf: integer }
    callback = function(args)
      if vim.api.nvim_buf_get_name(args.buf) == "" then
        return
      end
      local is_floatwin = vim.api.nvim_win_get_config(0).relative ~= ""
      if is_floatwin or (config.ignore_register and config.ignore_register(args.buf)) then
        return
      end
      async_call(frecency.register, args.buf, vim.api.nvim_buf_get_name(args.buf))
    end,
  })

  if config.bootstrap then
    database = require("frecency.database").new()
    async_call(function()
      database:start()
    end)
  end

  setup_done = true
  timer.track "setup() finish"
end

return {
  start = frecency.start,
  complete = frecency.complete,
  query = frecency.query,
  setup = setup,
}
