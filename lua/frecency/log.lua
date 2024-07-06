local config = require "frecency.config"
local log = require "plenary.log"

return setmetatable({}, {
  __index = function(_, key)
    return config.debug and log[key] or function() end
  end,
})
