local config = require "frecency.config"

---@type table?
local logger

-- NOTE: This keeps $DEBUG_PLENARY, which plenary.log read, as the switch for
-- the log level.
---@return table
local function get_logger()
  if not logger then
    logger = vim.log.new {
      name = "telescope-frecency",
      level = vim.env.DEBUG_PLENARY and vim.log.levels.DEBUG or vim.log.levels.INFO,
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
