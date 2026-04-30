---@meta
--- LuaCATS type definitions for etude.nvim. See `:help luacats`.

---@class etude
---@field setup fun(opts?: etude.UserConfig)
---@field pick fun()       Open the source picker (vim.ui.select).
---@field resume fun()     Resume the most recent source, or open the picker.
---@field stats fun()      Open the read-only stats float.
