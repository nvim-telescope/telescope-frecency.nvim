local finders = require "telescope.finders"
local log = require "frecency.log"

---@class FrecencyFinder
---@field config FrecencyFinderConfig
local Finder = {}

---@class FrecencyFinderConfig
---@field fs FrecencyFS
---@field entry_maker FrecencyEntryMaker
---@field initial_results table[]

---@param config FrecencyFinderConfig
---@return FrecencyFinder
Finder.new = function(config)
  return setmetatable({ config = config }, { __index = Finder })
end

---@class FrecencyFinderOptions
---@field need_scandir boolean
---@field workspace string?

---@param opts FrecencyFinderOptions
---@return table
function Finder:start(opts)
  local entry_maker = self.config.entry_maker:create(opts.workspace)
  if not opts.need_scandir then
    return finders.new_table {
      results = self.config.initial_results,
      entry_maker = entry_maker,
    }
  end
  log:debug { finder = opts }
  return finders.new_dynamic { entry_maker = entry_maker, fn = self:create_fn { path = opts.workspace } }
end

---@class FrecencyFinderCreateFnOptions
---@field path string

---@param opts FrecencyFinderCreateFnOptions
---@return fun(prompt: string?): table[]
function Finder:create_fn(opts)
  local it = self.config.fs:scan_dir(opts.path)
  local is_dead = false
  local results = vim.deepcopy(self.config.initial_results)
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
      table.insert(results, { path = vim.fs.joinpath(opts.path, name), score = 0 })
      count = count + 1
      if count >= 1000 then
        break
      end
    end
    return results
  end
end

return Finder
