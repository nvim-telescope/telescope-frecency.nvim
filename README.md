# telescope-frecency.nvim

A [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) extension that offers intelligent prioritization when selecting files from your editing history.

Using an implementation of Mozilla's [Frecency algorithm](https://web.archive.org/web/20210421120120/https://developer.mozilla.org/en-US/docs/Mozilla/Tech/Places/Frecency_algorithm) (used in [Firefox's address bar](https://support.mozilla.org/en-US/kb/address-bar-autocomplete-firefox)), files edited _frecently_ are given higher precedence in the list index.

As the extension learns your editing habits over time, the sorting of the list is dynamically altered to prioritize the files you're likely to need.

<img src="https://raw.githubusercontent.com/sunjon/images/master/gh_readme_telescope_frecency.png" alt="screenshot" width="800"/>

* _Scores shown in finder for demonstration purposes - disabled by default_

## Frecency: Sorting by 'frequency' _and_ 'recency'

'Frecency' is a score given to each unique file indexed in a file history database.

A timestamp is recorded once per session when a file is first loaded into a buffer.

The score is calculated using the age of the 10 (customizable) most recent timestamps and the total amount of times that the file has been loaded:

### Recency values (per timestamp)

| Timestamp age | Value |
| -------- | ---------- |
| 4 hours  | 100        |
| 1 day    | 80         |
| 3 days   | 60         |
| 1 week   | 40         |
| 1 month  | 20         |
| 90 days  | 10         |

### Score calculation

```lua
score = frequency * recency_score / max_number_of_timestamps
```
## What about files that are neither 'frequent' _or_ 'recent' ?

Frecency naturally works best for indexed files that have been given a reasonably high score.

New projects or rarely used files with generic names either don't get listed at all or can be buried under results with a higher score.

Frecency tackles this with *Workspace Filters*:

<img src="https://raw.githubusercontent.com/sunjon/images/master/frecency_workspace_folders.gif" alt="screenshot" width="800"/>

The workspace filter feature enables you to select from user defined _filter tags_ that map to a directory or collection of directories.
Filters are applied by entering `:workspace_tag:` anywhere in the query.
Filter name completion is available by pressing `<Tab>` after the first `:` character.

When a filter is applied, results are reduced to entries whose path is a descendant of the workspace directory.
The indexed results are optionally augmented with a listing of _all_ files found in a recurssive search of the workspace directory.
Non-indexed files are given a score of zero and appear below the 'frecent' entries.
When a non-indexed file is opened, it gains a score value and is available in future 'frecent' search results.

If the active buffer (prior to the finder being launched) is attached to an LSP server, an automatic `LSP` tag is available, which maps to the workspace directories provided by the language server.


## Requirements

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (required)
- [sqlite.lua][] (required)
- [nvim-web-devicons](https://github.com/kyazdani42/nvim-web-devicons) (optional)

[sqlite.lua]: https://github.com/kkharji/sqlite.lua

Timestamps and file records are stored in an [SQLite3](https://www.sqlite.org/index.html) database for persistence and speed.
This plugin uses `sqlite.lua` to perform the database transactions.

## Installation

### [Packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "nvim-telescope/telescope-frecency.nvim",
  config = function()
    require("telescope").load_extension "frecency"
  end,
  requires = { "kkharji/sqlite.lua" },
}
```

### [Lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nvim-telescope/telescope-frecency.nvim",
  config = function()
    require("telescope").load_extension "frecency"
  end,
  dependencies = { "kkharji/sqlite.lua" },
}
```

If no database is found when running Neovim with the plugin installed, a new one is created and entries from `shada` `v:oldfiles` are automatically imported.

## Usage

```vim
:Telescope frecency
```

or to map to a key:

```lua
vim.api.nvim_set_keymap("n", "<leader><leader>", "<Cmd>Telescope frecency<CR>")
```

Use a specific workspace tag:

```vim
:Telescope frecency workspace=CWD
```

or

```lua
vim.api.nvim_set_keymap("n", "<leader><leader>", "<Cmd>Telescope frecency workspace=CWD<CR>")
```

Filter tags are applied by typing the `:tag:` name (adding surrounding colons) in the finder query.
Entering `:<Tab>` will trigger omnicompletion for available tags.

## Configuration

See [default configuration](https://github.com/nvim-telescope/telescope.nvim#telescope-defaults) for full details on configuring Telescope.

- `db_root` (default: `vim.fn.stdpath "data"`)

  Path to parent directory of custom database location.
  Defaults to `$XDG_DATA_HOME/nvim` if unset.

- `default_workspace` (default: `nil`)

  Default workspace tag to filter by e.g. `'CWD'` to filter by default to the current directory. Can be overridden at query time by specifying another filter like `':*:'`.

- `disable_devicons` (default: `false`)

  Disable devicons (if available)

- `ignore_patterns` (default: `{ "*.git/*", "*/tmp/*", "term://*" }`)

  Patterns in this table control which files are indexed (and subsequently which you'll see in the finder results).

- `max_timestamps` (default: `10`)

  Set the max count of timestamps DB keeps when you open files. It ignores the value and use `10` if you set less than or equal to `0`.

  **CAUTION** When you reduce the value of this option, it removes old timestamps when you open the file. It is reasonable to set this value more than or equal to the default value: `10`.

- `show_filter_column` (default: `true`)

  Show the path of the active filter before file paths. In default, it uses the tail of paths for `'LSP'` and `'CWD'` tags. You can configure this by setting a table for this option.

   ```lua
   -- show the tail for "LSP", "CWD" and "FOO"
   show_filter_column = { "LSP", "CWD", "FOO" }
   ```

- `show_scores` (default : `false`)

  To see the scores generated by the algorithm in the results, set this to `true`.

- `show_unindexed` (default: `true`)

    Determines if non-indexed files are included in workspace filter results.

- `use_sqlite` (default: `true`) ***experimental feature***

  Use [sqlite.lua] `true` or native code `false`. See [*Remove dependency for sqlite.lua*](#user-content-remove-dependency-for-sqlitelua) for the detail.

- `workspaces` (default: `{}`)

    This table contains mappings of `workspace_tag` -> `workspace_directory`
    The key corresponds to the `:tag_name` used to select the filter in queries.
    The value corresponds to the top level directory by which results will be filtered.

### Example Configuration:

```lua
telescope.setup {
  extensions = {
    frecency = {
      db_root = "home/my_username/path/to/db_root",
      show_scores = false,
      show_unindexed = true,
      ignore_patterns = {"*.git/*", "*/tmp/*"},
      disable_devicons = false,
      workspaces = {
        ["conf"]    = "/home/my_username/.config",
        ["data"]    = "/home/my_username/.local/share",
        ["project"] = "/home/my_username/projects",
        ["wiki"]    = "/home/my_username/wiki"
      }
    }
  },
}
```

## Note for Database

### Location

The default location for the database is `$XDG_DATA_HOME/nvim` (eg `~/.local/share/nvim/` on linux).
This can be configured with the `db_root` config option.

### Maintainance

By default, frecency will prune files that no longer exist from the database.
In certain workflows, switching branches in a repository, that behaviour might not be desired.
The following configuration control this behaviour:

`db_safe_mode` - When this is enabled, the user will be prompted before any entries are removed from the database.
`auto_validate` - When this to false, stale entries will never be automatically removed.

The command `FrecencyValidate` can be used to clean the database when `auto_validate` is disabled.

```vim
" clean DB
:FrecencyValidate
" clean DB without prompts to confirm
:FrecencyValidate!
```

### Remove dependency for [sqlite.lua][]

***This is an experimental feature.***

In default, it uses SQLite3 library to access the DB. When `use_sqlite` option is set to `false`, it stores the whole data and saves them with encoding by `string.dump()` Lua function.

With this, we can remove the dependency for [sqlite.lua][] and obtain faster speed to open `:Telescope frecency`.

You can migrate from SQLite DB into native code by `:FrecencyMigrateDB` command. It converts data into native code, but does not delete the existent SQLite DB. You can use old SQLite logic by `use_sqlite = true` again.

## Highlight Groups

```vim
TelescopeBufferLoaded
TelescopePathSeparator
TelescopeFrecencyScores
TelescopeQueryFilter
```

TODO: describe highlight groups

## References

- [Mozilla: Frecency algorithm](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/Places/Frecency_algorithm)
