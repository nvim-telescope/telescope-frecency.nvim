local M = {}
local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local Path = require "plenary.path"
local util = require "frecency.util"
local os_home = vim.loop.os_homedir()
local os_path_sep = Path.path.sep
local actions = require "telescope.actions"
local conf = require("telescope.config").values
local entry_display = require "telescope.pickers.entry_display"
local finders = require "telescope.finders"
local Path = require "plenary.path"
local pickers = require "telescope.pickers"
local sorters = require "telescope.sorters"
local ts_util = require "telescope.utils"

---TODO: Describe FrecencyPicker fields

---@class FrecencyPicker
---@field db FrecencyDB: where the files will be stored
---@field results table
---@field active_filter string
---@field active_filter_tag string
---@field previous_buffer string
---@field cwd string
---@field lsp_workspaces table
---@field picker table
local M = {
  db = nil,
  results = {},
  active_filter = nil,
  active_filter_tag = nil,
  last_filter = nil,
  previous_buffer = nil,
  cwd = nil,
  lsp_workspaces = {},
  picker = {},
}
M.__index = M

---@class FrecencyConfig
---@field show_unindexed boolean: default true
---@field show_filter_column boolean: default true
---@field user_workspaces table: default {}
---@field disable_devicons boolean: default false
M.config = {
  show_scores = false,
  show_unindexed = true,
  show_filter_column = true,
  user_workspaces = {},
  disable_devicons = false,
}

---Setup Frecency Picker
---@param db FrecencyDB
---@param config FrecencyConfig
M.setup = function(db, config)
  M.db = db
  M.db.set_config(config)
  M.config = vim.tbl_extend("keep", config, M.config)
end

-- M.setup(require "frecency.db", {})

---Find files
---@param opts table: telescope picker opts
M.fd = function(opts)
  opts = opts or {}
  if not M.db.is_initialized then
    M.db.init()
  end
  M.previous_buffer, M.cwd = vim.fn.bufnr "%", vim.fn.expand(opts.cwd or vim.loop.cwd())
  M.update_results()
  M.picker = pickers.new(opts, {
    prompt_title = "Frecency",
    finder = finders.new_table { results = M.results, entry_maker = M.maker },
    previewer = conf.file_previewer(opts),
    sorter = sorters.get_substr_matcher(opts),
    on_input_filter_cb = function(query_text)
      local o = {}
      -- check for :filter: in query text
      local delim = M.config.filter_delimiter or ":"
      local matched, new_filter = query_text:match("^%s*(" .. delim .. "(%S+)" .. delim .. ")")
      if M.update_results(new_filter) then
        M.last_filter = new_filter
        o.updated_finder = finders.new_table { results = M.results, entry_maker = M.maker }
      end
      o.prompt = matched and query_text:sub(matched:len() + 1) or query_text
      return o
    end,
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace_if(function()
        return vim.fn.complete_info().pum_visible == 1
      end, function()
        local keys = vim.fn.complete_info().selected == -1 and "<C-e><Bs><Right>" or "<C-y><Right>:"
        local accept_completion = vim.api.nvim_replace_termcodes(keys, true, false, true)
        vim.api.nvim_feedkeys(accept_completion, "n", true)
      end)
      return true
    end,
  })
  M.picker:find()
  util.buf_set {
    M.picker.prompt_bufnr,
    options = { filetype = "frecency", completefunc = "frecency#FrecencyComplete" },
    mappings = {
      expr = true,
      ["i|<Tab>"] = "pumvisible() ? '<C-n>'  : '<C-x><C-u>'",
      ["i|<S-Tab>"] = "pumvisible() ? '<C-p>'  : ''",
    },
  }
end

---Update Frecency Picker result
---@param filter string
---@return boolean
---@TODO: make it more readable please :D
M.update_results = function(filter)
  local filter_updated = false
  local ws_dir = filter and M.config.user_workspaces[filter]

  if filter == "LSP" and not vim.tbl_isempty(M.lsp_workspaces) then
    ws_dir = M.lsp_workspaces[1]
  elseif filter == "CWD" then
    ws_dir = M.cwd
  end

  if ws_dir ~= M.active_filter then
    filter_updated = true
    M.active_filter, M.active_filter_tag = ws_dir, filter
  end

  if vim.tbl_isempty(M.results) or filter_updated then
    M.results = M.db.get_files { ws_dir = ws_dir, show_unindexed = M.config.show_unindexed, with_score = true }
  end
  return filter_updated
end

---Create entry maker function.
---@param entry table
---@return function
---FIXME: path transacted with icons being pre-appended instead of appended
M.maker = function(entry)
  local items = {}
  if M.config.show_scores then
    table.insert(items, { width = 8 })
  end

  if M.config.show_filter_column then
    local width = 0
    -- TODO: Only add +1 if M.show_filter_thing is true, +1 is for the trailing slash
    if M.active_filter and M.active_filter_tag == "LSP" then
      width = #(utils.path_tail(M.active_filter)) + 1
    elseif M.active_filter then
      width = #(Path:new(M.active_filter):make_relative(os_home)) + 1
    end
    table.insert(items, { width = width })
  end

  if not M.config.disable_devicons and has_devicons then
    table.insert(items, { width = 2 }) -- icon column
  end

  table.insert(items, { remaining = true })

  return {
    filename = entry.path,
    ordinal = entry.path,
    name = entry.path,
    score = entry.score,
    display = function(e)
      return entry_display.create {
        separator = "",
        items = items,
        hl_chars = { [os_path_sep] = "TelescopePathSeparator" },
      }(M.display_items(e))
    end,
  }
end

M.display_items = function(e)
  local items = M.config.show_scores and { { e.score, "TelescopeFrecencyScores" } } or {}

  -- TODO: store the column lengths here, rather than recalculating in get_display_cols()
  -- TODO: only include filter_paths column if M.show_filter_col is true

  table.insert(items, {
    (function()
      if M.active_filter_tag == "LSP" or M.active_filter_tag == "CWD" then
        return ts_util.path_tail(M.active_filter) .. os_path_sep
      elseif M.active_filter then
        return Path:new(M.active_filter):make_relative(os_home) .. os_path_sep
      else
        return ""
      end
    end)(),
    "Directory",
  })

  table.insert(items, {
    M.file_format(e.name),
    util.buf_is_loaded(e.name) and "TelescopeBufferLoaded" or "",
  })

  if has_devicons and not M.config.disable_devicons then
    icon, icon_highlight = devicons.get_icon(e.name, string.match(e.name, "%a+$"), { default = true })
    table.insert(items, { icon, icon_highlight })
  end
  return items
end

---Format filename. Mainly os_home to {~/} or current to {./}
---@param filename string
---@return string
M.file_format = function(filename)
  local original_filename = filename

  if M.active_filter then
    filename = Path:new(filename):make_relative(M.active_filter)
  else
    filename = Path:new(filename):make_relative(M.cwd)
    -- check relative to home/current
    if vim.startswith(filename, os_home) then
      filename = "~/" .. Path:new(filename):make_relative(os_home)
    elseif filename ~= original_filename then
      filename = "./" .. filename
    end
  end

  if M.tail_path then
    filename = util.path_tail(filename)
  elseif M.shorten_path then
    filename = util.path_shorten(filename)
  end

  return filename
end

---TODO: this seems to be forgotten and just exported in old implementation.
---@return table
M.workspace_tags = function()
  -- Add user config workspaces.
  -- TODO: validate that workspaces are existing directories
  local tags = {}
  for k, _ in pairs(M.config.user_workspaces) do
    table.insert(tags, k)
  end
  -- Add CWD filter
  --  NOTE: hmmm :cwd::lsp: is easier to write.
  table.insert(tags, "CWD")

  -- Add LSP workpace(s)
  local lsp_workspaces = vim.api.nvim_buf_call(M.previous_buffer, vim.lsp.buf.list_workspace_folders)
  if not vim.tbl_isempty(lsp_workspaces) then
    M.lsp_workspaces = lsp_workspaces
    table.insert(tags, "LSP")
  else
    M.lsp_workspaces = {}
  end

  -- TODO: sort tags - by collective frecency? (?????? is this still relevant)
  return tags
end

return M
