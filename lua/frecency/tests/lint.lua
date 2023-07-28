if not vim.env.LSP_CONFIG_PATH then
  print "cannot find nvim-lspconfig"
  vim.cmd.qa { bang = true }
end
vim.opt.runtimepath:append(vim.env.LSP_CONFIG_PATH)
require("lspconfig").lua_ls.setup { settings = { Lua = { diagnostics = { globals = { "vim" } } } } }
vim.api.nvim_create_autocmd("DiagnosticChanged", {
  callback = function(args)
    local diagnostics = args.data.diagnostics
    local filename = vim.api.nvim_buf_get_name(0)
    local out = vim.v.argv[#vim.v.argv]
    local fh = assert(io.open(out, "w"))
    for _, d in ipairs(diagnostics) do
      local f = vim.api.nvim_buf_get_name(d.bufnr)
      if f == filename then
        fh:write(("%s:%d:%d:%s\n"):format(filename, d.lnum + 1, d.col, d.message))
      end
    end
    fh:close()
    vim.cmd.qa { bang = true }
  end,
})
