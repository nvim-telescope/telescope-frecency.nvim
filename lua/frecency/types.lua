---@diagnostic disable: unused-local
-- NOTE: types below are borrowed from sqlite.lua

---@class sqlite_db @Main sqlite.lua object.
---@field uri string: database uri. it can be an environment variable or an absolute path. default ":memory:"
---@field opts sqlite_opts: see https://www.sqlite.org/pragma.html |sqlite_opts|
---@field conn sqlite_blob: sqlite connection c object.
---@field db sqlite_db: reference to fallback to when overwriting |sqlite_db| methods (extended only).

---@class sqlite_query_update @Query fileds used when calling |sqlite:update| or |sqlite_tbl:update|
---@field where table: filter down values using key values.
---@field set table: key and value to updated.

---@class sqlite_query_select @Query fileds used when calling |sqlite:select| or |sqlite_tbl:get|
---@field where table? filter down values using key values.
---@field keys table? keys to include. (default all)
---@field join table? (TODO: support)
---@field order_by table? { asc = "key", dsc = {"key", "another_key"} }
---@field limit number? the number of result to limit by
---@field contains table? for sqlite glob ex. { title = "fix*" }

---@alias sqlite_query_delete table<string, any>

---@generic T
---@alias sqlite_map_func fun(self: sqlite_tbl, mapper: fun(entry: table): T?): T[]

---@class sqlite_tbl @Main sql table class
---@field db sqlite_db: sqlite.lua database object.
---@field name string: table name.
---@field mtime number: db last modified time.
---@field count fun(self: sqlite_tbl): integer
---@field insert fun(self: sqlite_tbl, rows: table<string, any>|table<string, any>[]): integer
---@field update fun(self: sqlite_tbl, specs: sqlite_query_update): boolean
---@field get fun(self: sqlite_tbl, query: sqlite_query_select): table[]
---@field remove fun(self: sqlite_tbl, where: sqlite_query_delete): boolean
---@field map sqlite_map_func

---@class sqlite_opts @Sqlite3 Options (TODO: add sqlite option fields and description)
---@class sqlite_blob @sqlite3 blob object

---@class sqlite_lib
---@field cast fun(source: integer, as: string): string
---@field julianday fun(timestring: string?): integer

-- NOTE: types are borrowed from plenary.nvim

---@class PlenaryPath
---@field new fun(self: PlenaryPath|string, path: string?): PlenaryPath
---@field absolute fun(): string
---@field is_file fun(self: PlenaryPath): boolean
---@field filename string
---@field joinpath fun(self: PlenaryPath, ...): PlenaryPath
---@field make_relative fun(self: PlenaryPath, cwd: string): string
---@field path { sep: string }
---@field rm fun(self: PlenaryPath, opts: { recursive: boolean }?): nil

---@class PlenaryScanDirOptions
---@field hidden boolean if true hidden files will be added
---@field add_dirs boolean if true dirs will also be added to the results
---@field only_dirs boolean if true only dirs will be added to the results
---@field respect_gitignore boolean if true will only add files that are not ignored by the git
---@field depth integer depth on how deep the search should go
---@field search_pattern string|string[]|fun(path: string): boolean regex for which files will be added, string, table of strings, or fn(e) -> boolean
---@field on_insert fun(path: string): boolean           Will be called for each element
---@field silent boolean              if true will not echo messages that are not accessible

---@alias scan_dir fun(path: string, opts: PlenaryScanDirOptions): string[]

---@class PlenaryAsync
---@field control PlenaryAsyncControl
---@field util PlenaryAsyncUtil
local PlenaryAsync = {}

---@async
---@param f fun(): nil
---@return nil
function PlenaryAsync.run(f) end

---@class PlenaryAsyncControl
---@field channel PlenaryAsyncControlChannel

---@class PlenaryAsyncControlChannel
---@field mpsc fun(): PlenaryAsyncControlChannelTx, PlenaryAsyncControlChannelRx

---@class PlenaryAsyncControlChannelTx
---@field send fun(entry: FrecencyEntry?): nil
local PlenaryAsyncControlChannelTx = {}

---@class PlenaryAsyncControlChannelRx
local PlenaryAsyncControlChannelRx = {}

---@async
---@return FrecencyEntry?
function PlenaryAsyncControlChannelRx.recv() end

---@class PlenaryAsyncUtil
local PlenaryAsyncUtil = {}

---@async
---@param ms integer
---@return nil
function PlenaryAsyncUtil.sleep(ms) end

-- NOTE: types are for telescope.nvim

---@alias TelescopeEntryDisplayer fun(items: string[]): table

---@class TelescopeEntryDisplayOptions
---@field separator string?
---@field hl_chars table<string, string>?
---@field items string[]

---@class TelescopeEntryDisplay
---@field create fun(opts: TelescopeEntryDisplayOptions): TelescopeEntryDisplayer

---@class TelescopeUtils
---@field path_tail fun(path: string): string
---@field transform_path fun(opts: table, path: string): string
---@field buf_is_loaded fun(filename: string): boolean

---@class TelescopePicker
---@field clear_extra_rows fun(self: TelescopePicker, results_bufnr: integer): nil
---@field get_row fun(self: TelescopePicker, index: integer): integer
---@field manager TelescopeEntryManager|false
---@field prompt_bufnr integer
---@field prompt_prefix string
---@field results_bufnr integer?
---@field results_win integer?
---@field sorting_strategy 'ascending'|'descending'

---@class TelescopeEntryManager
---@field num_results fun(): integer

-- NOTE: types for default functions

---@class WinInfo
---@field topline integer
---@field botline integer
