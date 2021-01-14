# telescope-frecency.nvim

An implementation of Mozillas [Frecency algorithm](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/Places/Frecency_algorithm) for [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).

## Frecency: sorting by "frequency" and "recency"

Frecency is a score given to each unique file loaded into a Neovim buffer.
On each load a timestamp is recorded to a database. The score is calculated using the age of each of the timestamps and the amount of times the file has been loaded:

```
recency_score =
   timestamp_age = 240      => value = 100  -- past 4 hours 
   timestamp_age = 1440     => value = 80   -- past day     
   timestamp_age = 4320     => value = 60   -- past 3 days  
   timestamp_age = 10080    => value = 40   -- past week    
   timestamp_age = 43200    => value = 20   -- past month   
   timestamp_age = 129600   => value = 10   -- past 90 days

final_score  = frequency * recency_score / max_number_of_timestamps

```
## WIP

TODO

- [ ] Implement sorter based on frecency score
- [ ] Check file entries are valid via async job on VimClose


<img src="https://raw.githubusercontent.com/sunjon/images/master/gh_readme_telescope_frecency.png" height="600">

## Requirements

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (required)
- [sql.nvim](https://github.com/tami5/sql.nvim) (required)

Timestamps and file records are stored in an [SQLite3](https://www.sqlite.org/index.html) database for persistence and speed.
This plugin uses `sql.nvim` to perform the database transactions.



## Installation

TODO:

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
