---This object is intended to be used as a singleton, and is lazily loaded.
---When methods are called at the first time, it calls the constructor and
---setup() to be initialized.
---@class FrecencyInstance
---@field complete fun(findstart: 1|0, base: string): integer|''|string[]
---@field delete fun(path: string): nil
---@field register fun(bufnr: integer, datetime: string?): nil
---@field start fun(opts: FrecencyPickerOptions?): nil
---@field validate_database fun(force: boolean?): nil
local frecency = setmetatable({}, {
  __index = function(self, key)
    return function(...)
      local instance = rawget(self, "instance") --[[@as Frecency?]]
      if not instance then
        instance = require("frecency").new()
        instance:setup()
        rawset(self, "instance", instance)
      end
      return instance[key](instance, ...)
    end
  end,
})

return require("telescope").register_extension {
  exports = {
    frecency = frecency.start,
    complete = frecency.complete,
  },

  ---When this func is called, Frecency instance is NOT created but only
  ---configuration is done.
  setup = function(ext_config)
    require("frecency.config").setup(ext_config)

    vim.api.nvim_set_hl(0, "TelescopeBufferLoaded", { link = "String", default = true })
    vim.api.nvim_set_hl(0, "TelescopePathSeparator", { link = "Directory", default = true })
    vim.api.nvim_set_hl(0, "TelescopeFrecencyScores", { link = "Number", default = true })
    vim.api.nvim_set_hl(0, "TelescopeQueryFilter", { link = "WildMenu", default = true })

    ---@param cmd_info { bang: boolean }
    vim.api.nvim_create_user_command("FrecencyValidate", function(cmd_info)
      frecency.validate_database(cmd_info.bang)
    end, { bang = true, desc = "Clean up DB for telescope-frecency" })

    vim.api.nvim_create_user_command("FrecencyDelete", function(info)
      local path_string = info.args == "" and "%:p" or info.args
      local path = vim.fn.expand(path_string) --[[@as string]]
      frecency.delete(path)
    end, { nargs = "?", complete = "file", desc = "Delete entry from telescope-frecency" })

    local group = vim.api.nvim_create_augroup("TelescopeFrecency", {})
    vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWritePost" }, {
      desc = "Update database for telescope-frecency",
      group = group,
      ---@param args { buf: integer }
      callback = function(args)
        local is_floatwin = vim.api.nvim_win_get_config(0).relative ~= ""
        if not is_floatwin then
          frecency.register(args.buf)
        end
      end,
    })
  end,

  health = function()
    if vim.F.npcall(require, "nvim-web-devicons") then
      vim.health.ok "nvim-web-devicons installed."
    else
      vim.health.info "nvim-web-devicons is not installed."
    end
    if vim.fn.executable "rg" == 1 then
      vim.health.ok "ripgrep installed."
    elseif vim.fn.executable "fdfind" == 1 then
      vim.health.ok "fdfind installed."
    elseif vim.fn.executable "fd" == 1 then
      vim.health.ok "fd installed."
    else
      vim.health.info "No suitable find executable found."
    end
  end,
}
