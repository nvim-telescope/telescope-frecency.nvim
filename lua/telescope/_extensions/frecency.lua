local has_telescope, telescope = pcall(require, "telescope")

-- TODO: make dependency errors occur in a better way
if not has_telescope then
  error("This plugin requires telescope.nvim (https://github.com/nvim-telescope/telescope.nvim)")
end

-- start the database client
local db_client = require("telescope._extensions.frecency.db_client")
-- vim.defer_fn(db_client.init, 100) -- TODO: this is a crappy attempt to lessen loadtime impact, use VimEnter?
db_client.init()


-- finder code

-- local actions       = require "telescope.actions"
local entry_display = require "telescope.pickers.entry_display"
local finders       = require "telescope.finders"
local pickers       = require "telescope.pickers"
local previewers    = require "telescope.previewers"
-- local sorters       = require "telescope.sorters"
local sorters       = require "telescope._extensions.frecency.sorter"
-- local conf          = require('telescope.config').values
local path = require('telescope.path')
local utils = require('telescope.utils')

local frecency = function(opts)
  opts = opts or {}

  local cwd = vim.fn.expand(opts.cwd or vim.fn.getcwd())
  -- opts.lsp_workspace_filter = true
  -- TODO: decide on how to handle cwd or lsp_workspace for pathname shorten?
  local results = db_client.get_file_scores(opts) -- TODO: pass `filter_workspace` option

  local os_path_sep = vim.loop.os_uname().sysname == "Windows" and "\\" or "/"

  local displayer = entry_display.create {
    separator = "",
    hl_chars = {[os_path_sep] = "TelescopePathSeparator"},
    items = {
      { width = 8 },
      { remaining = true },
    },
  }

  -- TODO: look into why this gets called so much
  local make_display = function(entry)
    local bufnr = vim.fn.bufnr
    local buf_is_loaded = vim.api.nvim_buf_is_loaded

    local filename = entry.name

    local hl_filename = buf_is_loaded(bufnr(filename)) and "TelescopeBufferLoaded" or ""

    if opts.tail_path then
      filename = utils.path_tail(filename)
    elseif opts.shorten_path then
      filename = utils.path_shorten(filename)
    end

    filename = path.make_relative(filename, cwd)


    -- TODO: remove score from display; only there for debug
    return displayer {
      {entry.score, "Directory"},
      {filename, hl_filename},
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
    -- previewer = conf.file_previewer(opts),
    sorter    = sorters.get_substr_matcher(opts),
    -- sorter    = conf.file_sorter(opts)
  }):find()
end

local validate = function()
  print("validate db")
  db_client.validate()
end


return telescope.register_extension {
  exports = {
    frecency = frecency,
    validate = validate,
  },
}
