-- Minimal reproduction harness. Run with:
--   nvim -u repro/repro.lua
-- ... then :Etude to try the plugin.

vim.env.LAZY_STDPATH = ".repro"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

require("lazy.minit").repro({
  spec = {
    {
      "etude.nvim",
      dir = vim.fn.getcwd(),
      lazy = false,
      opts = {
        -- Drop a few practice files here to exercise the file-source path:
        -- sources = {
        --   { path = "~/notes/practice/sample.txt", name = "Sample" },
        -- },
      },
    },
  },
})
