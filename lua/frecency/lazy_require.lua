-- Compat: neoplen.async dropped its `uv` submodule in telescope.nvim commit
-- b9b203f ("feat(plenary): remove unused async") because telescope itself does
-- not use it. frecency relies on the async-aware libuv wrappers, so until
-- upstream restores them (asked for in nvim-telescope/telescope.nvim#3647),
-- re-attach plenary's uv_async to the neoplen.async module table. Runs once
-- per session as a side effect of loading this module.
do
  local ok, async = pcall(require, "neoplen.async")
  if ok and not async.uv then
    async.uv = require "plenary.async.uv_async"
  end
end

---@param module string
return function(module)
  return setmetatable({}, {
    __index = function(_, key)
      return require(module)[key]
    end,
    __call = function(_, ...)
      return require(module)(...)
    end,
  })
end
