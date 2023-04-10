local has_telescope, telescope = pcall(require, "telescope")

-- TODO: make sure scandir unindexed have opts.ignore_patterns applied
-- TODO: make filters handle mulitple directories

if not has_telescope then
  error "This plugin requires telescope.nvim (https://github.com/nvim-telescope/telescope.nvim)"
end

local config = {}

local state = {
  results = {},
  active_filter = nil,
  active_filter_tag = nil,
  last_filter = nil,
  previous_buffer = nil,
  cwd = nil,
  show_scores = false,
  default_workspace = nil,
  user_workspaces = {},
  lsp_workspaces = {},
  picker = {},
}

-- returns `true` if workspaces exist
---@param bufnr number
---@param force? boolean
---@return boolean workspaces_exist
local function fetch_lsp_workspaces(bufnr, force)
  if not vim.tbl_isempty(state.lsp_workspaces) and not force then
    return true
  end

  local lsp_workspaces = vim.api.nvim_buf_call(bufnr, vim.lsp.buf.list_workspace_folders)
  if not vim.tbl_isempty(lsp_workspaces) then
    state.lsp_workspaces = lsp_workspaces
    return true
  end

  state.lsp_workspaces = {}
  return false
end

local function get_workspace_tags()
  -- Add user config workspaces. TODO: validate that workspaces are existing directories
  local tags = {}
  for k, _ in pairs(state.user_workspaces) do
    table.insert(tags, k)
  end

  -- Add CWD filter
  table.insert(tags, "CWD")

  -- Add LSP workpace(s)
  if fetch_lsp_workspaces(state.previous_buffer, true) then
    table.insert(tags, "LSP")
  end

  -- print(vim.inspect(tags))
  -- TODO: sort tags - by collective frecency?
  return tags
end

local frecency = function(opts)
  local has_devicons, devicons = pcall(require, "nvim-web-devicons")
  local entry_display = require "telescope.pickers.entry_display"
  local finders = require "telescope.finders"
  local Path = require "plenary.path"
  local pickers = require "telescope.pickers"
  local utils = require "telescope.utils"

  local db_client = require "telescope._extensions.frecency.db_client"

  -- start the database client
  db_client.init(
    config.db_root,
    config.ignore_patterns,
    vim.F.if_nil(config.db_safe_mode, true),
    vim.F.if_nil(config.auto_validate, true)
  )

  opts = opts or {}

  state.previous_buffer = vim.fn.bufnr "%"
  state.cwd = vim.fn.expand(opts.cwd or vim.fn.getcwd())

  fetch_lsp_workspaces(state.previous_buffer)

  local os_home = vim.loop.os_homedir()

  local function should_show_tail()
    local filters = type(state.show_filter_column) == "table" and state.show_filter_column or { "LSP", "CWD" }
    return vim.tbl_contains(filters, state.active_filter_tag)
  end

  local function get_display_cols()
    local directory_col_width = 0
    if state.active_filter then
      if should_show_tail() then
        -- TODO: Only add +1 if opts.show_filter_thing is true, +1 is for the trailing slash
        directory_col_width = #(utils.path_tail(state.active_filter)) + 1
      else
        directory_col_width = #(Path:new(state.active_filter):make_relative(os_home)) + 1
      end
    end
    local res = {}
    res[1] = state.show_scores and { width = 8 } or nil
    if has_devicons and not state.disable_devicons then
      table.insert(res, { width = 2 }) -- icon column
    end
    if state.show_filter_column then
      table.insert(res, { width = directory_col_width })
    end
    table.insert(res, { remaining = true })
    return res
  end
  local os_path_sep = utils.get_separator()

  local displayer = entry_display.create {
    separator = "",
    hl_chars = { [os_path_sep] = "TelescopePathSeparator" },
    items = get_display_cols(),
  }

  if not opts.path_display then
    opts.path_display = function (path_opts, filename)
      local original_filename = filename

      filename = Path:new(filename):make_relative(path_opts.cwd)
      if not state.active_filter then
        if vim.startswith(filename, os_home) then
          filename = "~/" .. Path:new(filename):make_relative(os_home)
        elseif filename ~= original_filename then
          filename = "./" .. filename
        end
      end

      return filename
    end
  end

  local function filepath_formatter(path_opts0)
    local path_opts = {}
    for k, v in pairs(path_opts0) do
      path_opts[k] = v
    end

    return function (filename)
      path_opts.cwd = state.active_filter or state.cwd
      return utils.transform_path(path_opts, filename)
    end
  end

  local formatter = filepath_formatter(opts)

  local bufnr, buf_is_loaded, display_filename, hl_filename, display_items, icon, icon_highlight
  local make_display = function(entry)
    bufnr = vim.fn.bufnr
    buf_is_loaded = vim.api.nvim_buf_is_loaded
    display_filename = entry.name
    hl_filename = buf_is_loaded(bufnr(display_filename)) and "TelescopeBufferLoaded" or ""
    display_filename = formatter(display_filename)

    display_items = state.show_scores and { { entry.score, "TelescopeFrecencyScores" } } or {}

    if has_devicons and not state.disable_devicons then
      icon, icon_highlight = devicons.get_icon(entry.name, string.match(entry.name, "%a+$"), { default = true })
      table.insert(display_items, { icon, icon_highlight })
    end

    -- TODO: store the column lengths here, rather than recalculating in get_display_cols()
    if state.show_filter_column then
      local filter_path = ""
      if state.active_filter then
        if should_show_tail() then
          filter_path = utils.path_tail(state.active_filter) .. os_path_sep
        else
          filter_path = Path:new(state.active_filter):make_relative(os_home) .. os_path_sep
        end
      end

      table.insert(display_items, { filter_path, "Directory" })
    end

    table.insert(display_items, { display_filename, hl_filename })

    return displayer(display_items)
  end

  local update_results = function(filter)
    local filter_updated = false

    -- validate tag
    local ws_dir = filter and state.user_workspaces[filter]
    if filter == "LSP" and not vim.tbl_isempty(state.lsp_workspaces) then
      ws_dir = state.lsp_workspaces[1]
    end

    if filter == "CWD" then
      ws_dir = state.cwd
    end

    if ws_dir ~= state.active_filter then
      filter_updated = true
      state.active_filter = ws_dir
      state.active_filter_tag = filter
    end

    if vim.tbl_isempty(state.results) or db_client.has_updated_results() or filter_updated then
      state.results = db_client.get_file_scores(state.show_unindexed, ws_dir)
    end
    return filter_updated
  end

  -- populate initial results
  update_results()

  local entry_maker = function(entry)
    return {
      filename = entry.filename,
      display = make_display,
      ordinal = entry.filename,
      name = entry.filename,
      score = entry.score,
    }
  end

  local delim = opts.filter_delimiter or ":"
  local filter_re = "^%s*(" .. delim .. "(%S+)" .. delim .. ")"

  state.picker = pickers.new(opts, {
    prompt_title = "Frecency",
    on_input_filter_cb = function(query_text)
      -- check for :filter: in query text
      local matched, new_filter = query_text:match(filter_re)
      if matched then
        query_text = query_text:sub(matched:len() + 1)
      end
      new_filter = new_filter or opts.workspace or state.default_workspace

      local new_finder
      local results_updated = update_results(new_filter)
      if results_updated then
        displayer = entry_display.create {
          separator = "",
          hl_chars = { [os_path_sep] = "TelescopePathSeparator" },
          items = get_display_cols(),
        }

        state.last_filter = new_filter
        new_finder = finders.new_table {
          results = state.results,
          entry_maker = entry_maker,
        }
        -- print(vim.inspect(new_finder))
      end

      return { prompt = query_text, updated_finder = new_finder }
    end,
    attach_mappings = function(prompt_bufnr)
      require "telescope.actions".select_default:replace_if(function()
        local compinfo = vim.fn.complete_info()
        return compinfo.pum_visible == 1
      end, function()
        local compinfo = vim.fn.complete_info()
        local keys = compinfo.selected == -1 and "<C-e><Bs><Right>" or "<C-y><Right>:"
        local accept_completion = vim.api.nvim_replace_termcodes(keys, true, false, true)
        vim.api.nvim_feedkeys(accept_completion, "n", true)
      end)

      return true
    end,
    finder = finders.new_table {
      results = state.results,
      entry_maker = entry_maker,
    },
    previewer = require("telescope.config").values.file_previewer(opts),
    sorter = require'telescope.sorters'.get_substr_matcher(opts),
  })
  state.picker:find()

  vim.api.nvim_buf_set_option(state.picker.prompt_bufnr, "filetype", "TelescopePrompt")
  vim.api.nvim_buf_set_option(state.picker.prompt_bufnr, "completefunc", "frecency#FrecencyComplete")
  vim.api.nvim_buf_set_keymap(
    state.picker.prompt_bufnr,
    "i",
    "<Tab>",
    "pumvisible() ? '<C-n>'  : '<C-x><C-u>'",
    { expr = true, noremap = true }
  )
  vim.api.nvim_buf_set_keymap(
    state.picker.prompt_bufnr,
    "i",
    "<S-Tab>",
    "pumvisible() ? '<C-p>'  : ''",
    { expr = true, noremap = true }
  )
end

local function set_config_state(opt_name, value, default)
  state[opt_name] = value == nil and default or value
end

local function checkhealth()
  local has_sql, _ = pcall(require, "sqlite")
  if has_sql then
    vim.health.report_ok "sql.nvim installed."
    -- return "MOOP"
  else
    vim.health.report_error "Need sql.nvim to be installed."
  end
  if pcall(require, "nvim-web-devicons") then
    vim.health.report_ok "nvim-web-devicons installed."
  else
    vim.health.report_info "nvim-web-devicons is not installed."
  end
end

return telescope.register_extension {
  setup = function(ext_config)
    set_config_state("db_root", ext_config.db_root, nil)
    set_config_state("show_scores", ext_config.show_scores, false)
    set_config_state("show_unindexed", ext_config.show_unindexed, true)
    set_config_state("show_filter_column", ext_config.show_filter_column, true)
    set_config_state("user_workspaces", ext_config.workspaces, {})
    set_config_state("disable_devicons", ext_config.disable_devicons, false)
    set_config_state("default_workspace", ext_config.default_workspace, nil)
    config = vim.deepcopy(ext_config)
  end,
  exports = {
    frecency = frecency,
    get_workspace_tags = get_workspace_tags,
    validate_db = function(...)
      require"telescope._extensions.frecency.db_client".validate(...)
    end
  },
  health = checkhealth,
}
