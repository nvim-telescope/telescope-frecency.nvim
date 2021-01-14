# telescope-frecency.nvim

An implementation of Mozillas [Frecency algorithm](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/Places/Frecency_algorithm) for [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).

## Frecency: sorting by "frequency" and "recency."

Frecency is a score given to each file loaded into a Neovim buffer.
The score is calculated by combining the timestamps recorded on each load and how recent the timestamps are:

```
score  = frequency * recency_score / number_of_timestamps

```



<img src="https://raw.githubusercontent.com/sunjon/images/master/gh_readme_telescope_packer.png" height="600">

## Requirements

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (required)
- [sql.nvim](https://github.com/tami5/sql.nvim) (required)

Timestamps and file records are stored in an [SQLite3](https://www.sqlite.org/index.html) database for persistence and speed.
This plugin uses `sql.nvim` to perform the database transactions.



## Installation

TODO:

```
abc
```

## Configuration

Function for keymaps

```lua
lua require("telescope").extensions.frecency.frecency(opts)
```

```
:Telescope frecency
```
