local log = require "plenary.log"

local function make_msg(...)
  local msg = ""
  for _, obj in ipairs { ... } do
    msg = msg .. " " .. type(obj) == "string" and obj or vim.inspect(obj, { indent = "", newline = "" })
  end
  return ("%.6f %s"):format(os.clock(), msg)
end

return {
  debug = function(...)
    log.debug(make_msg(...))
  end,
  info = function(...)
    log.info(make_msg(...))
  end,
}
