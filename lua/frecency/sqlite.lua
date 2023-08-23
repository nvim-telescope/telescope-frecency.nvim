---@class FrecencySqlite
---@field can_use boolean
---@field lib sqlite_lib
---@overload fun(opts: table): FrecencySqliteDB

return setmetatable({}, {
  __index = function(_, k)
    if k == "lib" then
      return require("sqlite").lib
    elseif k == "can_use" then
      return not not vim.F.npcall(require, "sqlite")
    end
  end,
  __call = function(_, opts)
    return require "sqlite"(opts)
  end,
}) --[[@as FrecencySqlite]]
