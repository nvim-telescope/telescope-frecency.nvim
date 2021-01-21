local has_telescope, telescope = pcall(require, "telescope")

-- TODO: make dependency errors occur in a better way
if not has_telescope then
  error("This plugin requires telescope.nvim (https://github.com/nvim-telescope/telescope.nvim)")
end

-- finder code
local conf          = require('telescope.config').values
local entry_display = require "telescope.pickers.entry_display"
local finders       = require "telescope.finders"
local path          = require('telescope.path')
local pickers       = require "telescope.pickers"
local utils         = require('telescope.utils')

local os_home       = vim.loop.os_homedir()
local os_path_sep   = utils.get_separator()
local show_scores = false
local db_client

local frecency = function(opts)
  opts = opts or {}

  local cwd = vim.fn.expand(opts.cwd or vim.fn.getcwd())
  -- opts.lsp_workspace_filter = true
  -- TODO: decide on how to handle cwd or lsp_workspace for pathname shorten?
  local results = db_client.get_file_scores(opts) -- TODO: pass `filter_workspace` option

  local display_cols = {}
  display_cols[1] = show_scores and {width = 8} or nil
  table.insert(display_cols, {remaining = true})

  local displayer = entry_display.create {
    separator = "",
    hl_chars = {[os_path_sep] = "TelescopePathSeparator"},
    items = display_cols
  }

  -- TODO: look into why this gets called so much
  local bufnr, buf_is_loaded, filename, hl_filename, display_items, original_filename

  local make_display = function(entry)
    bufnr = vim.fn.bufnr
    buf_is_loaded = vim.api.nvim_buf_is_loaded

    filename = entry.name
    hl_filename = buf_is_loaded(bufnr(filename)) and "TelescopeBufferLoaded" or ""

    original_filename = filename

    if opts.tail_path then
      filename = utils.path_tail(filename)
    elseif opts.shorten_path then
      filename = utils.path_shorten(filename)
    else -- check relative to home/current
      filename = path.make_relative(filename, cwd)
      if vim.startswith(filename, os_home) then
        filename = "~/" ..  path.make_relative(filename, os_home)
      elseif filename ~= original_filename then
        filename = "./" .. filename
      end
    end

    display_items = show_scores and {{entry.score, "Directory"}} or {}
    table.insert(display_items, {filename, hl_filename})

    return displayer(display_items)
  end

  pickers.new(opts, {
    prompt_title = "Frecency",
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
    sorter    = conf.file_sorter(opts),
  }):find()
end

return telescope.register_extension {
  setup = function(ext_config)
    show_scores = ext_config.show_scores or false

    -- start the database client
    db_client = require("telescope._extensions.frecency.db_client")
    db_client.init(ext_config.ignore_patterns)
  end,
  exports = {
    frecency = frecency,
  },
}
