local os_util = require "frecency.os_util"

---@class FrecencyConfig: FrecencyRawConfig
---@field private values FrecencyRawConfig
local Config = {}

---@class FrecencyRawConfig
---@field recency_values { age: integer, value: integer }[] default: see lua/frecency/config.lua
---@field auto_validate boolean default: true
---@field db_root string default: vim.fn.stdpath "data"
---@field db_safe_mode boolean default: true
---@field db_validate_threshold integer default: 10
---@field default_workspace? string default: nil
---@field disable_devicons boolean default: false
---@field filter_delimiter string default: ":"
---@field hide_current_buffer boolean default: false
---@field ignore_patterns string[] default: { "*.git/*", "*/tmp/*", "term://*" }
---@field matcher "default"|"fuzzy"|"fuzzy_full" default: "default"
---@field max_timestamps integer default: 10
---@field show_filter_column boolean|string[] default: true
---@field show_scores boolean default: false
---@field show_unindexed boolean default: true
---@field workspace_scan_cmd? "LUA"|string[] default: nil
---@field workspaces table<string, string> default: {}

---@return FrecencyConfig
Config.new = function()
  local default_values = {
    auto_validate = true,
    db_root = vim.fn.stdpath "data",
    db_safe_mode = true,
    db_validate_threshold = 10,
    default_workspace = nil,
    disable_devicons = false,
    filter_delimiter = ":",
    hide_current_buffer = false,
    ignore_patterns = os_util.is_windows and { [[*.git\*]], [[*\tmp\*]], "term://*" }
      or { "*.git/*", "*/tmp/*", "term://*" },
    matcher = "default",
    max_timestamps = 10,
    recency_values = {
      { age = 240, value = 100 }, -- past 4 hours
      { age = 1440, value = 80 }, -- past day
      { age = 4320, value = 60 }, -- past 3 days
      { age = 10080, value = 40 }, -- past week
      { age = 43200, value = 20 }, -- past month
      { age = 129600, value = 10 }, -- past 90 days
    },
    show_filter_column = true,
    show_scores = false,
    show_unindexed = true,
    workspace_scan_cmd = nil,
    workspaces = {},
  }
  ---@type table<string, boolean>
  local keys = {
    recency_values = true,
    auto_validate = true,
    db_root = true,
    db_safe_mode = true,
    db_validate_threshold = true,
    default_workspace = true,
    disable_devicons = true,
    filter_delimiter = true,
    hide_current_buffer = true,
    ignore_patterns = true,
    matcher = true,
    max_timestamps = true,
    show_filter_column = true,
    show_scores = true,
    show_unindexed = true,
    workspace_scan_cmd = true,
    workspaces = true,
  }
  return setmetatable({
    values = default_values,
  }, {
    __index = function(self, key)
      if key == "values" then
        return rawget(self, key)
      elseif keys[key] then
        return rawget(rawget(self, "values"), key)
      end
      return rawget(Config, key)
    end,
  })
end

local config = Config.new()

---@return FrecencyRawConfig
Config.get = function()
  return config.values
end

---@param ext_config any
---@return nil
Config.setup = function(ext_config)
  local opts = vim.tbl_extend("force", config.values, ext_config or {})
  vim.validate {
    recency_values = { opts.recency_values, "t" },
    auto_validate = { opts.auto_validate, "b" },
    db_root = { opts.db_root, "s" },
    db_safe_mode = { opts.db_safe_mode, "b" },
    db_validate_threshold = { opts.db_validate_threshold, "n" },
    default_workspace = { opts.default_workspace, "s", true },
    disable_devicons = { opts.disable_devicons, "b" },
    filter_delimiter = { opts.filter_delimiter, "s" },
    hide_current_buffer = { opts.hide_current_buffer, "b" },
    ignore_patterns = { opts.ignore_patterns, "t" },
    matcher = {
      opts.matcher,
      function(v)
        return type(v) == "string" and (v == "default" or v == "fuzzy" or v == "fuzzy_full")
      end,
      '"default" or "fuzzy"',
    },
    max_timestamps = {
      opts.max_timestamps,
      function(v)
        return type(v) == "number" and v > 0
      end,
      "positive number",
    },
    show_filter_column = { opts.show_filter_column, { "b", "t" }, true },
    show_scores = { opts.show_scores, "b" },
    show_unindexed = { opts.show_unindexed, "b" },
    workspace_scan_cmd = { opts.workspace_scan_cmd, { "s", "t" }, true },
    workspaces = { opts.workspaces, "t" },
  }
  config.values = opts
end

return config
