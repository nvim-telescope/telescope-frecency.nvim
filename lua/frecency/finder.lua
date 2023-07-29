local finders = require "telescope.finders"
local log = require "frecency.log"

---@class FrecencyFinder
---@field private entry_maker FrecencyEntryMaker
---@field private fs FrecencyFS
local Finder = {}

---@param entry_maker FrecencyEntryMaker
---@param fs FrecencyFS
---@return FrecencyFinder
Finder.new = function(entry_maker, fs)
  return setmetatable({ entry_maker = entry_maker, fs = fs }, { __index = Finder })
end

---@class FrecencyFinderOptions
---@field need_scandir boolean
---@field workspace string?

---@param initial_results table
---@param opts FrecencyFinderOptions
---@return table
function Finder:start(initial_results, opts)
  local entry_maker = self.entry_maker:create(opts.workspace)
  if not opts.need_scandir then
    return finders.new_table {
      results = initial_results,
      entry_maker = entry_maker,
    }
  end
  log:debug { finder = opts }
  return finders.new_dynamic { entry_maker = entry_maker, fn = self:create_fn(initial_results, opts.workspace) }
end

---@param initial_results table
---@param path string
---@return fun(prompt: string?): table[]
function Finder:create_fn(initial_results, path)
  local it = self.fs:scan_dir(path)
  local is_dead = false
  local results = vim.deepcopy(initial_results)
  local called = 0
  ---@param prompt string?
  ---@return table[]
  return function(prompt)
    if is_dead then
      return results
    end
    called = called + 1
    log:debug { called = called }
    local count = 0
    while true do
      local ok, name = pcall(it)
      if not ok then
        is_dead = true
        break
      end
      table.insert(results, { path = vim.fs.joinpath(path, name), score = 0 })
      count = count + 1
      if count >= 1000 then
        break
      end
    end
    return results
  end
end

return Finder
