local Default = require "frecency.sorter.default"
local Opened = require "frecency.sorter.opened"
local SameRepo = require "frecency.sorter.same_repo"

---@param text string
local function parse_text(text)
  local entries = {}
  for line in vim.gsplit(text, "\n", { plain = true, trimempty = true }) do
    local part = vim.split(line, "%s+", { trimempty = true })
    if #part == 2 then
      table.insert(entries, { score = tonumber(part[1]), path = part[2] })
    end
  end
  assert(#entries > 0)
  return entries
end

local entries = [[
   10  /path/to/project_A/style.css
   20  /path/to/project_B/main.c
   40  /path/to/project_C/lib/main.ts
   60  /path/to/project_A/image.jpg
   80  /path/to/project_B/Makefile
  100  /path/to/project_A/index.html
]]

describe("frecency.sorter", function()
  for _, c in ipairs {
    {
      M = Default,
      name = "Default",
      entries = [[
        100  /path/to/project_A/index.html
         80  /path/to/project_B/Makefile
         60  /path/to/project_A/image.jpg
         40  /path/to/project_C/lib/main.ts
         20  /path/to/project_B/main.c
         10  /path/to/project_A/style.css
      ]],
    },
    {
      M = Opened,
      name = "Opened",
      entries = [[
         80  /path/to/project_B/Makefile
         60  /path/to/project_A/image.jpg
        100  /path/to/project_A/index.html
         40  /path/to/project_C/lib/main.ts
         20  /path/to/project_B/main.c
         10  /path/to/project_A/style.css
      ]],
    },
    {
      M = SameRepo,
      name = "SameRepo",
      entries = [[
        100  /path/to/project_A/index.html
         80  /path/to/project_B/Makefile
         60  /path/to/project_A/image.jpg
         20  /path/to/project_B/main.c
         10  /path/to/project_A/style.css
         40  /path/to/project_C/lib/main.ts
      ]],
    },
  } do
    it(("%s sorter returns valid entries"):format(c.name), function()
      local originals = {
        nvim_list_bufs = vim.api.nvim_list_bufs,
        nvim_buf_get_name = vim.api.nvim_buf_get_name,
        nvim_buf_is_loaded = vim.api.nvim_buf_is_loaded,
        root = vim.fs.root,
      }
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.api.nvim_list_bufs = function()
        return { 1, 2 }
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.api.nvim_buf_get_name = function(bufnr)
        return ({
          "/path/to/project_A/image.jpg",
          "/path/to/project_B/Makefile",
          "/path/to/project_A/index.html",
        })[bufnr]
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.api.nvim_buf_is_loaded = function(bufnr)
        return ({ true, true, false })[bufnr]
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fs.root = function(path, _)
        return (path:match "(.*project_.)")
      end
      local sorter = c.M.new()
      ---@diagnostic disable-next-line: undefined-field
      assert.are.same(parse_text(c.entries), sorter:sort(parse_text(entries)))
      vim.api.nvim_list_bufs = originals.nvim_list_bufs
      vim.api.nvim_buf_get_name = originals.nvim_buf_get_name
      vim.api.nvim_buf_is_loaded = originals.nvim_buf_is_loaded
      vim.fs.root = originals.root
    end)
  end
end)
