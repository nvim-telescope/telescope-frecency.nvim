local config = require "frecency.config"

---@type table?
local logger

-- NOTE: neoplen.log (vendored in telescope.nvim) no longer reads
-- $DEBUG_PLENARY as plenary.log did, so this creates its own logger and keeps
-- the same switch for the log level.
---@return table
local function get_logger()
  if not logger then
    logger = require("neoplen.log").new {
      plugin = "telescope-frecency",
      level = vim.env.DEBUG_PLENARY and "debug" or "info",
    }
  end
  return logger
end

return setmetatable({}, {
  __index = function(_, key)
    return config.debug and vim.schedule_wrap(function(...)
      get_logger()[key](...)
    end) or function() end
  end,
})
