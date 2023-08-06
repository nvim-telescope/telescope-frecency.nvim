---@type Frecency?
local frecency

return {
  ---@param opts FrecencyConfig?
  setup = function(opts)
    frecency = require("frecency.frecency").new(opts)
    frecency:setup()
  end,
  ---@param opts FrecencyPickerOptions
  start = function(opts)
    if frecency then
      frecency:start(opts)
    end
  end,
  ---@param findstart 1|0
  ---@param base string
  ---@return integer|''|string[]
  complete = function(findstart, base)
    if frecency then
      return frecency:complete(findstart, base)
    end
    return ""
  end,
  ---@return Frecency
  frecency = function()
    return assert(frecency)
  end,
}
