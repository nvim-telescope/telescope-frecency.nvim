local uv = vim.uv or vim.loop
local Path = require "plenary.path"

---@param entries string[]
---@return PlenaryPath the top dir of tree
---@return fun(): nil sweep all entries
local function make_tree(entries)
  local dir = Path:new(Path.new(assert(uv.fs_mkdtemp "tests_XXXXXX")):absolute())
  for _, entry in ipairs(entries) do
    dir:joinpath(entry):touch { parents = true }
  end
  return dir, function()
    dir:rm { recursive = true }
  end
end

return { make_tree = make_tree }
