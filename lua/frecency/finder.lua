local scandir = require "plenary.scandir"

local Finder = {}

Finder.new = function(opts)
  return setmetatable({
    chunk = opts.results or {},
    count = 0,
    opts = opts,
    scan_opts = { hidden = false, add_dirs = false, only_dirs = false, respect_gitignore = true, depth = 999 },
  }, { __index = Finder, __call = Finder.__call })
end

function Finder:close()
  if self.cancel then
    self.cancel()
  end
end

function Finder:make_process(process_result)
  return function()
    for _, path in ipairs(self.chunk) do
      local entry = self.opts.entry_maker(path)
      if entry then
        self.count = self.count + 1
        entry.index = self.count
        if process_result(entry) then
          break
        end
      end
    end
    self.chunk = {}
  end
end

function Finder:__call(_, process_result, process_complete)
  local process = self:make_process(process_result)
  if not self.opts.ws_dir or not self.opts.show_unindexed then
    process()
    process_complete()
  else
    self.scan_opts.on_insert = function(path)
      table.insert(self.chunk, path)
      if #self.chunk >= 10000 then
        vim.schedule(process)
        vim.print("on_insert: " .. self.count)
      end
    end
    self.scan_opts.on_exit = function()
      if #self.chunk > 0 then
        process()
      end
      vim.print("on_exit:   " .. self.count)
      process_complete()
    end
    self.cancel = scandir.scan_dir_async(self.opts.ws_dir, self.scan_opts)
  end
end

return Finder
