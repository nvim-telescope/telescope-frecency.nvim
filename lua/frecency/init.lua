---This object is intended to be used as a singleton, and is lazily loaded.
---When methods are called at the first time, it calls the constructor and
---setup() to be initialized.
---@class FrecencyInstance
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
        rawset(self, "instance", require("frecency.klass").new())
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

  require("frecency.config").setup(ext_config)

  vim.api.nvim_set_hl(0, "TelescopeBufferLoaded", { link = "String", default = true })
  vim.api.nvim_set_hl(0, "TelescopePathSeparator", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "TelescopeFrecencyScores", { link = "Number", default = true })
  vim.api.nvim_set_hl(0, "TelescopeQueryFilter", { link = "WildMenu", default = true })

  ---@param cmd_info { bang: boolean }
  vim.api.nvim_create_user_command("FrecencyValidate", function(cmd_info)
    async_call(frecency.validate_database, cmd_info.bang)
  end, { bang = true, desc = "Clean up DB for telescope-frecency" })

  vim.api.nvim_create_user_command("FrecencyDelete", function(info)
    local path_string = info.args == "" and "%:p" or info.args
    local path = vim.fn.expand(path_string) --[[@as string]]
    async_call(frecency.delete, path)
  end, { nargs = "?", complete = "file", desc = "Delete entry from telescope-frecency" })

  local group = vim.api.nvim_create_augroup("TelescopeFrecency", {})
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWritePost" }, {
    desc = "Update database for telescope-frecency",
    group = group,
    ---@param args { buf: integer }
    callback = function(args)
      local is_floatwin = vim.api.nvim_win_get_config(0).relative ~= ""
      if not is_floatwin then
        async_call(frecency.register, args.buf)
      end
    end,
  })

  setup_done = true
end

return {
  start = frecency.start,
  complete = frecency.complete,
  query = frecency.query,
  setup = setup,
}
