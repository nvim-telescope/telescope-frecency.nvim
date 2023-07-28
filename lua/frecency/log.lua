---@class FrecencyLog
---@field count integer
---@field dev boolean
local Log = {}

Log.new = function()
  return setmetatable({ count = 0, dev = false }, { __index = Log })
end

---@param fmt any
---@param args any[]
---@param level integer
function Log:log(fmt, args, level)
  local function dump(v)
    return type(v) == "table" and vim.inspect(v, { indent = " ", newline = "" }) or v
  end
  local msg = #args == 0 and dump(fmt) or fmt:format(unpack(vim.tbl_map(dump, args)))
  self.count = self.count + 1
  vim.notify(("[Telescope-Frecency: %d]: %s"):format(self.count, msg), level)
end

---@param fmt any
---@param ... any
function Log:info(fmt, ...)
  self:log(fmt, { ... }, vim.log.levels.INFO)
end

---@param fmt any
---@param ... any
function Log:debug(fmt, ...)
  if self.dev then
    self:log(fmt, { ... }, vim.log.levels.DEBUG)
  end
end

return Log.new()
