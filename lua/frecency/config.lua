local os_util = require "frecency.os_util"

---Type to use when users write their own config.
---@class FrecencyOpts
---@field recency_values? { age: integer, value: integer }[] default: see lua/frecency/config.lua
---@field auto_validate? boolean default: true
---@field bootstrap? boolean default: true
---@field db_root? string default: vim.fn.stdpath "state"
---@field db_safe_mode? boolean default: true
---@field db_validate_threshold? integer default: 10
---@field db_version? "v1"|"v2" default: "v1"
---@field debug? boolean default: false
---@field debug_timer? boolean|fun(event: string): nil default: false
---@field default_workspace? string default: nil
---@field disable_devicons? boolean default: false
---@field enable_prompt_mappings? boolean default: false
---@field filter_delimiter? string default: ":"
---@field hide_current_buffer? boolean default: false
---@field ignore_patterns? string[] default: { "*.git/*", "*/tmp/*", "term://*" }
---@field ignore_register? fun(bufnr: integer): boolean
---@field matcher? "default"|"fuzzy" default: "default"
---@field scoring_function? fun(recency: integer, fzy_score: number): number default: see lua/frecency/config.lua
---@field max_timestamps? integer default: 10
---@field path_display? table default: nil
---@field preceding? "opened"|"same_repo" default: nil
---@field show_filter_column? boolean|string[] default: true
---@field show_scores? boolean default: false
---@field show_unindexed? boolean default: true
---@field unregister_hidden? boolean default: false
---@field workspace_scan_cmd? "LUA"|string[] default: nil
---@field workspaces? table<string, string|string[]> default: {}

---@class FrecencyConfig: FrecencyRawConfig
---@field ext_config FrecencyRawConfig
---@field private cached_ignore_regexes? string[]
---@field private values FrecencyRawConfig
local Config = {}

---@class FrecencyRawConfig
---@field recency_values { age: integer, value: integer }[] default: see lua/frecency/config.lua
---@field auto_validate boolean default: true
---@field bootstrap boolean default: true
---@field db_root string default: vim.fn.stdpath "state"
---@field db_safe_mode boolean default: true
---@field db_validate_threshold integer default: 10
---@field db_version "v1"|"v2" default: "v1"
---@field debug boolean default: false
---@field debug_timer boolean|fun(event: string): nil default: false
---@field default_workspace? string default: nil
---@field disable_devicons boolean default: false
---@field enable_prompt_mappings boolean default: false
---@field filter_delimiter string default: ":"
---@field hide_current_buffer boolean default: false
---@field ignore_patterns string[] default: { "*.git/*", "*/tmp/*", "term://*" }
---@field ignore_register? fun(bufnr: integer): boolean default: nil
---@field matcher "default"|"fuzzy" default: "default"
---@field scoring_function fun(recency: integer, fzy_score: number): number default: see lua/frecency/config.lua
---@field max_timestamps integer default: 10
---@field path_display? table default: nil
---@field preceding? "opened"|"same_repo" default: nil
---@field show_filter_column boolean|string[] default: true
---@field show_scores boolean default: false
---@field show_unindexed boolean default: true
---@field unregister_hidden boolean default: false
---@field workspace_scan_cmd? "LUA"|string[] default: nil
---@field workspaces table<string, string|string[]> default: {}

---@return FrecencyConfig
Config.new = function()
  ---@type table<string, boolean>
  local keys = {
    recency_values = true,
    auto_validate = true,
    bootstrap = true,
    db_root = true,
    db_safe_mode = true,
    db_validate_threshold = true,
    db_version = true,
    debug = true,
    debug_timer = true,
    default_workspace = true,
    disable_devicons = true,
    enable_prompt_mappings = true,
    filter_delimiter = true,
    hide_current_buffer = true,
    ignore_patterns = true,
    ignore_register = true,
    matcher = true,
    max_timestamps = true,
    path_display = true,
    preceding = true,
    scoring_function = true,
    show_filter_column = true,
    show_scores = true,
    show_unindexed = true,
    unregister_hidden = true,
    workspace_scan_cmd = true,
    workspaces = true,
  }
  return setmetatable({
    cached_ignore_regexes = {},
    ext_config = {},
    values = Config.default_values,
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

---@type FrecencyRawConfig
Config.default_values = {
  auto_validate = true,
  bootstrap = true,
  db_root = vim.fn.stdpath "state" --[[@as string]],
  db_safe_mode = true,
  db_validate_threshold = 10,
  db_version = "v1",
  debug = false,
  debug_timer = false,
  default_workspace = nil,
  disable_devicons = false,
  enable_prompt_mappings = false,
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
  ---@param recency integer
  ---@param fzy_score number
  ---@return number
  scoring_function = function(recency, fzy_score)
    local score = (10 / (recency == 0 and 1 or recency)) - 1 / fzy_score
    -- HACK: -1 means FILTERED, so return a bit smaller one.
    return score == -1 and -1.000001 or score
  end,
  show_filter_column = true,
  show_scores = false,
  show_unindexed = true,
  unregister_hidden = false,
  workspace_scan_cmd = nil,
  workspaces = {},
}

local config = Config.new()

---@return FrecencyRawConfig
Config.get = function()
  return config.values
end

---@return string[]
Config.ignore_regexes = function()
  if not config.cached_ignore_regexes then
    config.cached_ignore_regexes = vim
      .iter(config.ignore_patterns)
      :map(function(pattern)
        local regex = vim.pesc(pattern):gsub("%%%*", ".*"):gsub("%%%?", ".")
        return "^" .. regex .. "$"
      end)
      :totable()
  end
  return config.cached_ignore_regexes
end

---@param ext_config any
---@return nil
Config.setup = function(ext_config)
  local opts = vim.tbl_extend("force", Config.default_values, ext_config or {})
  if vim.fn.has "nvim-0.11" == 1 then
    vim.validate("recency_values", opts.recency_values, "table")
    vim.validate("auto_validate", opts.auto_validate, "boolean")
    vim.validate("bootstrap", opts.bootstrap, "boolean")
    vim.validate("db_root", opts.db_root, "string")
    vim.validate("db_safe_mode", opts.db_safe_mode, "boolean")
    vim.validate("db_validate_threshold", opts.db_validate_threshold, "number")
    vim.validate("db_version", opts.db_version, function(v)
      return v == "v1" or v == "v2"
    end, false, '"v1" or "v2"')
    vim.validate("debug", opts.debug, "boolean")
    vim.validate("debug_timer", opts.debug_timer, { "boolean", "function" })
    vim.validate("default_workspace", opts.default_workspace, "string", true)
    vim.validate("disable_devicons", opts.disable_devicons, "boolean")
    vim.validate("enable_prompt_mappings", opts.enable_prompt_mappings, "boolean")
    vim.validate("filter_delimiter", opts.filter_delimiter, "string")
    vim.validate("hide_current_buffer", opts.hide_current_buffer, "boolean")
    vim.validate("ignore_patterns", opts.ignore_patterns, "table")
    vim.validate("matcher", opts.matcher, function(v)
      return type(v) == "string" and (v == "default" or v == "fuzzy")
    end, '"default" or "fuzzy"')
    vim.validate("max_timestamps", opts.max_timestamps, function(v)
      return type(v) == "number" and v > 0
    end, "positive number")
    vim.validate("preceding", opts.preceding, function(v)
      return v == "opened" or v == "same_repo" or v == nil
    end, '"opened" or "same_repo" or nil')
    vim.validate("show_filter_column", opts.show_filter_column, { "boolean", "table" }, true)
    vim.validate("show_scores", opts.show_scores, "boolean")
    vim.validate("show_unindexed", opts.show_unindexed, "boolean")
    vim.validate("unregister_hidden", opts.unregister_hidden, "boolean")
    vim.validate("workspace_scan_cmd", opts.workspace_scan_cmd, { "string", "table" }, true)
    vim.validate("workspaces", opts.workspaces, "table")
  else
    ---@diagnostic disable: assign-type-mismatch
    -- TODO: remove this for deprecating 0.10 in the future
    vim.validate {
      ---@diagnostic disable: assign-type-mismatch
      recency_values = { opts.recency_values, "t" },
      auto_validate = { opts.auto_validate, "b" },
      bootstrap = { opts.bootstrap, "b" },
      db_root = { opts.db_root, "s" },
      db_safe_mode = { opts.db_safe_mode, "b" },
      db_validate_threshold = { opts.db_validate_threshold, "n" },
      db_version = {
        opts.db_version,
        function(v)
          return v == "v1" or v == "v2"
        end,
        '"v1"',
      },
      debug = { opts.debug, "b" },
      debug_timer = { opts.debug_timer, { "b", "f" } },
      default_workspace = { opts.default_workspace, "s", true },
      disable_devicons = { opts.disable_devicons, "b" },
      enable_prompt_mappings = { opts.enable_prompt_mappings, "b" },
      filter_delimiter = { opts.filter_delimiter, "s" },
      hide_current_buffer = { opts.hide_current_buffer, "b" },
      ignore_patterns = { opts.ignore_patterns, "t" },
      matcher = {
        opts.matcher,
        function(v)
          return type(v) == "string" and (v == "default" or v == "fuzzy")
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
      preceding = {
        opts.preceding,
        function(v)
          return v == "opened" or v == "same_repo" or v == nil
        end,
        '"opened" or "same_repo" or nil',
      },
      show_filter_column = { opts.show_filter_column, { "b", "t" }, true },
      show_scores = { opts.show_scores, "b" },
      show_unindexed = { opts.show_unindexed, "b" },
      unregister_hidden = { opts.unregister_hidden, "b" },
      workspace_scan_cmd = { opts.workspace_scan_cmd, { "s", "t" }, true },
      workspaces = { opts.workspaces, "t" },
      ---@diagnostic enable: assign-type-mismatch
    }
    ---@diagnostic enable: assign-type-mismatch
  end
  config.cached_ignore_regexes = nil
  config.ext_config = ext_config
  config.values = opts
end

return config
