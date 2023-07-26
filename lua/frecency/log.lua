---@class FrecencyLog
---@field count integer
---@field dev boolean
local Log = {}

Log.new = function()
  return setmetatable({ count = 0, dev = false }, { __index = Log })
end

---@param fmt string
---@param args any[]
---@param level integer
function Log:log(fmt, args, level)
  args = vim.tbl_map(function(v)
    return type(v) == "table" and vim.inspect(v, { indent = " ", newline = "" }) or v
  end, args)
  self.count = self.count + 1
  vim.notify(("[Telescope-Frecency: %d]: " .. fmt):format(self.count, unpack(args)), level)
end

---@param fmt string
---@param ... any
function Log:info(fmt, ...)
  self:log(fmt, { ... }, vim.log.levels.INFO)
end

---@param fmt string
---@param ... any
function Log:debug(fmt, ...)
  if self.dev then
    self:log(fmt, { ... }, vim.log.levels.DEBUG)
  end
end

return Log.new()
