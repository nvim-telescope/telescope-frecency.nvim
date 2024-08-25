local config = require "frecency.config"
local lazy_require = require "frecency.lazy_require"
local log = lazy_require "plenary.log"

return setmetatable({}, {
  __index = function(_, key)
    return config.debug and vim.schedule_wrap(function(...)
      log[key](...)
    end) or function() end
  end,
})
