# telescope-frecency.nvim

A [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) extension that offers intelligent prioritization when selecting files from your editing history.

Using an implementation of Mozilla's [Frecency algorithm](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/Places/Frecency_algorithm) (used in [Firefox's address bar](https://support.mozilla.org/en-US/kb/address-bar-autocomplete-firefox)), files edited _frecently_ are given higher precedence in the list index.

As the extension learns your editing habits over time, the sorting of the list is dynamically altered to prioritize the files you're likely to need.

<img src="https://raw.githubusercontent.com/sunjon/images/master/gh_readme_telescope_frecency.png" alt="screenshot" width="800"/>

* _Scores shown in finder for demonstration purposes - disabled by default_

## Frecency: Sorting by 'frequency' _and_ 'recency'

'Frecency' is a score given to each unique file indexed in a file history database.

A timestamp is recorded once per session when a file is first loaded into a buffer.

The score is calculated using the age of the 10 most recent timestamps and the total amount of times that the file has been loaded:

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

```
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
- [sqlite.lua](https://github.com/kkharji/sqlite.lua) (required)
- [nvim-web-devicons](https://github.com/kyazdani42/nvim-web-devicons) (optional)

Timestamps and file records are stored in an [SQLite3](https://www.sqlite.org/index.html) database for persistence and speed.
This plugin uses `sqlite.lua` to perform the database transactions.

## Installation

### [Packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "nvim-telescope/telescope-frecency.nvim",
  config = function()
    require"telescope".load_extension("frecency")
  end,
  requires = {"kkharji/sqlite.lua"}
}
```

_TODO: add installation instructions for other package managers_

If no database is found when running Neovim with the plugin installed, a new one is created and entries from `shada` `v:oldfiles` are automatically imported.

## Usage

```
:Telescope frecency
```
..or to map to a key:

```lua
vim.api.nvim_set_keymap("n", "<leader><leader>", "<Cmd>lua require('telescope').extensions.frecency.frecency()<CR>", {noremap = true, silent = true})
```
Filter tags are applied by typing the `:tag:` name (adding surrounding colons) in the finder query.
Entering `:<Tab>` will trigger omnicompletion for available tags.

## Configuration

See [default configuration](https://github.com/nvim-telescope/telescope.nvim#telescope-defaults) for full details on configuring Telescope.

- `db_root` (default: `nil`)

  Path to parent directory of custom database location.
  Defaults to `$XDG_DATA_HOME/nvim` if unset.

- `default_workspace` (default: `nil`)

  Default workspace tag to filter by e.g. `'CWD'` to filter by default to the current directory. Can be overridden at query time by specifying another filter like `':*:'`.

- `ignore_patterns` (default: `{"*.git/*", "*/tmp/*"}`)

  Patterns in this table control which files are indexed (and subsequently which you'll see in the finder results).

- `show_scores` (default : `false`)

  To see the scores generated by the algorithm in the results, set this to `true`.

- `workspaces` (default: {})

    This table contains mappings of `workspace_tag` -> `workspace_directory`
    The key corresponds to the `:tag_name` used to select the filter in queries.
    The value corresponds to the top level directory by which results will be filtered.

- `show_unindexed` (default: `true`)

    Determines if non-indexed files are included in workspace filter results.

- `devicons_disabled` (default: `false`)

  Disable devicons (if available)


### Example Configuration:

```
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

### SQL database location

The default location for the sqlite3 database is `$XDG_DATA_HOME/nvim` (eg `~/.local/share/nvim/` on linux).
This can be configured with the `db_root` config option.

### SQL database maintainance

By default, frecency will prune files that no longer exist from the database.
In certain workflows, switching branches in a repository, that behaviour might not be desired.
The following configuration control this behaviour:

`db_safe_mode` - When this is enabled, the user will be prompted before any entries are removed from the database.
`auto_validate` - When this to false, stale entries will never be automatically removed.

The command `FrecencyValidate` can be used to clean the database when `auto_validate` is disabled.

### Highlight Groups

```vim
TelescopeBufferLoaded
TelescopePathSeparator
TelescopeFrecencyScores
TelescopeQueryFilter
```

TODO: describe highlight groups

## References

- [Mozilla: Frecency algorithm](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/Places/Frecency_algorithm)
