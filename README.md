# telescope-frecency.nvim

An implementation of Mozilla's [Frecency algorithm](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/Places/Frecency_algorithm) for [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).

## Frecency: sorting by "frequency" and "recency"

Frecency is a score given to each unique file loaded into a Neovim buffer.

A timestamp is recorded to a database on each file load.

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

## WIP


TODO:

- [x] Implement sorter based on frecency score
- [ ] Improve substring matcher to support multiple terms
- [ ] Check file entries are valid via async job on VimClose

<img src="https://raw.githubusercontent.com/sunjon/images/master/gh_readme_telescope_frecency.png" alt="screenshot" width="800"/>

* _Scores shown in finder for illustration purposes only_

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

## Configuration

Function for keymaps

```lua
lua require("telescope").extensions.frecency.frecency(opts)
```

```
:Telescope frecency
```

## References

- [Stack Engineering: A faster smarter quick switcher](https://slack.engineering/a-faster-smarter-quick-switcher/)
- [Mozilla Frecency algorithm](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/Places/Frecency_algorithm)
