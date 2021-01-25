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
local sorters       = require "telescope.sorters"
local utils         = require('telescope.utils')

local os_home       = vim.loop.os_homedir()
local os_path_sep   = utils.get_separator()
local show_scores = false
local db_client

local tags = {
  ["conf"] = "/home/sunjon/.config",
  ["data"] = "/home/sunjon/.local/share",
  ["etc"] = "/etc",
  ["alpha"] = "/home/sunjon/alpha",
  ["project"] = "/home/sunjon/projects",
  ["wiki"] = "/home/sunjon/wiki"
}

local frecency = function(opts)
  opts = opts or {}

  local state = {}
  state.results = {}
  state.active_filter = nil
  state.cwd = vim.fn.expand(opts.cwd or vim.fn.getcwd())

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
      filename = path.make_relative(filename, state.cwd)
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


  local update_results = function(filter)
    local filter_updated = false

    -- validate tag
    local tag_dir = filter and tags[filter]
    if tag_dir ~= state.active_filter then
      filter_updated = true
      state.active_filter = tag_dir
      -- print(("Matched tag: [%s] - %s"):format(filter, tag_dir))
    end

    if vim.tbl_isempty(state.results) or filter_updated then
      state.results = db_client.get_file_scores(opts, tag_dir)
    end
    return filter_updated
  end

  -- populate initial results
  update_results()

  local entry_maker = function(entry)
    return {
      value   = entry.filename,
      display = make_display,
      ordinal = entry.filename,
      name    = entry.filename,
      score   = entry.score
    }
  end

  local picker = pickers.new(opts, {
    prompt_title = "Frecency",
    on_input_filter_cb = function(query_text)
      local fc = opts.filter_delimiter or ":"
      local filter
      -- check for active filter
      local new_finder
      filter = query_text:gmatch(fc .. "%S+" .. fc)()

      if filter then
        query_text = query_text:gsub(filter, "")
        filter     = filter:gsub(fc, "")
      end

      if (filter or (state.active_filter and not filter))
        and update_results(filter) then
        new_finder = finders.new_table {
          results     = state.results,
          entry_maker = entry_maker
        }
      end

      return query_text, new_finder
    end,
    finder = finders.new_table {
      results     = state.results,
      entry_maker = entry_maker
    },
    previewer = conf.file_previewer(opts),
    sorter    = sorters.get_substr_matcher(opts),
  })
  picker:find()
  print("Prompt: " .. picker.prompt_bufnr)
  -- local prompt_winid = vim.fn.bufwinid(picker.prompt_bufnr)
  -- vim.api.nvim_buf_set_option(picker.prompt_bufnr, "completefunc", "v:lua.require('telescope').extensions.frecency.competefunc()")
  vim.api.nvim_buf_set_option(picker.prompt_bufnr, "completefunc", "frecency#FrecencyComplete")
  -- TODO: make keymaps play nicely with Telescope
  vim.cmd("imap <expr> <buffer> <Tab> pumvisible() ? '<C-n>' : '<C-x><C-u>'")
  vim.cmd("imap <expr> <buffer> <Cr>  pumvisible() ? '<C-y>:' : '<CR>'")
  vim.cmd("imap <expr> <buffer> <Esc> pumvisible() ? '<C-e>:' : '<Esc>'")
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
