local M = {}

local function join_paths(...)
  return table.concat({ ... }, "/")
end

function M.dir(path, opts)
  opts = opts or {}

  vim.validate {
    path = { path, { "string" } },
    depth = { opts.depth, { "number" }, true },
    skip = { opts.skip, { "function" }, true },
  }

  if not opts.depth or opts.depth == 1 then
    local fs = vim.loop.fs_scandir(vim.fs.normalize(path))
    return function()
      return vim.loop.fs_scandir_next(fs)
    end, function() end
  end

  local cancelled
  local function is_cancelled()
    return cancelled
  end
  local function cancel()
    cancelled = true
  end

  --- @async
  return coroutine.wrap(function()
    local dirs = { { path, 1 } }
    while not is_cancelled() and #dirs > 0 do
      local dir0, level = unpack(table.remove(dirs, 1))
      local dir = level == 1 and dir0 or join_paths(path, dir0)
      local fs = vim.loop.fs_scandir(vim.fs.normalize(dir))
      while not is_cancelled() and fs do
        local name, t = vim.loop.fs_scandir_next(fs)
        if not name then
          break
        end
        local f = level == 1 and name or join_paths(dir0, name)
        if not is_cancelled() then
          coroutine.yield(f, t)
        else
          break
        end
        if opts.depth and level < opts.depth and t == "directory" and (not opts.skip or opts.skip(f) ~= false) then
          dirs[#dirs + 1] = { f, level + 1 }
        end
      end
    end
  end),
    cancel
end

return M
