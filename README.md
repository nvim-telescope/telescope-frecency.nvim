# telescope-frecency.nvim

A [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) extension that offers intelligent prioritization when selecting files from your editing history.

Using an implementation of Mozilla's [Frecency algorithm](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/Places/Frecency_algorithm) (used in [Firefox's address bar](https://support.mozilla.org/en-US/kb/address-bar-autocomplete-firefox)), files edited _frecently_ are given higher precedence in the list index.
As the extension learns your editing habits over time, the sorting of the list is dynamically altered to priotize the files you're likely to need.

<img src="https://raw.githubusercontent.com/sunjon/images/master/gh_readme_telescope_frecency.png" alt="screenshot" width="800"/>

* _Scores shown in finder for illustration purposes only_

## Frecency: sorting by "frequency" and "recency"

'Frecency' is a score given to each unique file indexed in a file history database.

A timestamp is recorded to once per session when a file is loaded into a buffer.

The score is calculated using the age of the 10 most recent timestamps and the total amount of times the file has been loaded:

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

## Requirements

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (required)
- [sql.nvim](https://github.com/tami5/sql.nvim) (required)

Timestamps and file records are stored in an [SQLite3](https://www.sqlite.org/index.html) database for persistence and speed.
This plugin uses `sql.nvim` to perform the database transactions.

## Installation

TODO: add installation instructions for other package managers

```
use {
  "sunjon/telescope-frecency",
  config = function()
    require"telescope".load_extension("frecency")
  end
}

```
If no database is found when running Neovim with the plugin installed, a new one is created and entries from `shada` `v:oldfiles` are automatically imported.

## Configuration

Function for keymaps

```lua
lua require("telescope").extensions.frecency.frecency(opts)
```

```
:Telescope frecency
```

## References

- [Mozilla: Frecency algorithm](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/Places/Frecency_algorithm)
