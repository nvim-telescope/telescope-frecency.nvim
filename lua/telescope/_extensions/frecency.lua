local has_telescope, telescope = pcall(require, "telescope")

-- TODO: make dependency errors occur in a better way
if not has_telescope then
  error("This plugin requires telescope.nvim (https://github.com/nvim-telescope/telescope.nvim)")
end

-- start the database client
print("start")
local db_client = require("telescope._extensions.frecency.db_client")
vim.defer_fn(db_client.init, 100) -- TODO: this is a crappy attempt to lessen loadtime impact, use VimEnter?


-- finder code

-- local actions       = require "telescope.actions"
local entry_display = require "telescope.pickers.entry_display"
local finders       = require "telescope.finders"
local pickers       = require "telescope.pickers"
local previewers    = require "telescope.previewers"
local sorters       = require "telescope.sorters"
local conf          = require('telescope.config').values
local path = require('telescope.path')
local utils = require('telescope.utils')

local frecency = function(opts)
  opts = opts or {}

  local cwd = vim.fn.expand(opts.cwd or vim.fn.getcwd())
  local results = db_client.get_file_scores()
  -- print(vim.inspect(results))

  local displayer = entry_display.create {
    separator = "",
    hl_chars = { ["/"] = "TelescopePathSeparator"},
    items = {
      { width = 8 },
      { remaining = true },
    },
  }

  -- TODO: look into why this gets called so much
  local make_display = function(entry)
    local filename = entry.name

    if opts.tail_path then
      filename = utils.path_tail(filename)
    elseif opts.shorten_path then
      filename = utils.path_shorten(filename)
    end

    filename = path.make_relative(filename, cwd)

    -- TODO: remove score from display; only there for debug
    return displayer {
      {entry.score, "Directory"}, filename
    }
  end

  pickers.new(opts, {
    prompt_title = "Frecency files",
    finder = finders.new_table {
      results = results,
      entry_maker = function(entry)
        return {
          value   = entry.filename,
          display = make_display,
          ordinal = entry.filename,
          name    = entry.filename,
          score   = entry.score
        }
      end,
    },
    previewer = conf.file_previewer(opts),
    sorter = sorters.get_generic_fuzzy_sorter(), -- TODO: do we have to have our own sorter? we only want filtering
  }):find()
end


return telescope.register_extension {
  exports = {
    frecency = frecency,
  },
}