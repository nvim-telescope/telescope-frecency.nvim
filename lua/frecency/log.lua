local config = require "frecency.config"
local lazy_require = require "frecency.lazy_require"
local log = lazy_require "neoplen.log"

-- Compat: neoplen.log dropped plenary.log's "create the outfile parent dir if
-- missing" step when it stopped depending on plenary.path. The default outfile
-- is `stdpath("log")/neoplen.log`, and on a fresh XDG_STATE_HOME (e.g. CI
-- sandboxes or our test runner) that directory does not exist yet, so the
-- first log line throws ENOENT. Ensure the dir exists once at load time.
-- Track restoration upstream in nvim-telescope/telescope.nvim#3647.
do
  local log_dir = vim.fn.stdpath "log" --[[@as string]]
  if vim.fn.isdirectory(log_dir) == 0 then
    vim.fn.mkdir(log_dir, "p")
  end
end

return setmetatable({}, {
  __index = function(_, key)
    return config.debug and vim.schedule_wrap(function(...)
      log[key](...)
    end) or function() end
  end,
})
