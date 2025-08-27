# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project
telescope-frecency.nvim is a Neovim Telescope extension implementing Mozilla's Frecency algorithm for intelligent file prioritization.

## Build/Test Commands
- Run all tests: `bin/run-tests`
- Run specific test: `bin/run-tests lua/frecency/tests/test_file.lua`
- Run with verbose logs: `bin/run-tests -v`
- Use custom Neovim binary: `bin/run-tests -e /path/to/nvim`

## Code Style
- Language: Lua
- Indentation: 2 spaces
- Typing: Use LuaLS annotations (---@class, ---@param, etc.)
- Naming: snake_case for variables/functions
- Error handling: Check errors with assertions
- Documentation: Docstrings for public functions
- Async patterns: Use async/await with plenary.async
- Testing: Test files in lua/frecency/tests/ with *_spec.lua suffix
- Imports: Standard Lua require statements
- Type validation: Use vim.validate for config validation