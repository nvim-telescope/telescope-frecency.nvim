local uv = vim.uv or vim.loop
local Path = require "plenary.path"

---@return PlenaryPath
---@return fun(): nil close swwp all entries
local function tmpdir()
  local dir = Path:new(Path:new(assert(uv.fs_mkdtemp "tests_XXXXXX")):absolute())
  return dir, function()
    dir:rm { recursive = true }
  end
end

---@param entries string[]
---@return PlenaryPath dir the top dir of tree
---@return fun(): nil close sweep all entries
local function make_tree(entries)
  local dir, close = tmpdir()
  for _, entry in ipairs(entries) do
    ---@diagnostic disable-next-line: undefined-field
    dir:joinpath(entry):touch { parents = true }
  end
  return dir, close
end

return { make_tree = make_tree, tmpdir = tmpdir }
