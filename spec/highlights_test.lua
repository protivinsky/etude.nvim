-- Verify that highlights.setup propagates Normal's bg to the float surface.
--   nvim --headless -l spec/highlights_test.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Pretend we're under a colorscheme: set Normal and a brighter NormalFloat
-- (the inconsistency this code is meant to fix).
vim.api.nvim_set_hl(0, "Normal", { fg = "#abb2bf", bg = "#21252b" })
vim.api.nvim_set_hl(0, "NormalFloat", { fg = "#abb2bf", bg = "#2e323a" })
vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#5c6370" })

local ns = vim.api.nvim_create_namespace("etude")
require("etude.highlights").setup(ns)

local function ns_hl(name)
  return vim.api.nvim_get_hl(ns, { name = name, link = false })
end

local nf = ns_hl("NormalFloat")
print("ns NormalFloat = " .. vim.inspect(nf))
assert(nf.bg == 0x21252b, "expected bg to match Normal (0x21252b), got " .. tostring(nf.bg))

local fb = ns_hl("FloatBorder")
print("ns FloatBorder = " .. vim.inspect(fb))
assert(fb.bg == 0x21252b, "border bg should match Normal bg, got " .. tostring(fb.bg))
assert(fb.fg == 0x5c6370, "border fg should be preserved")

local eob = ns_hl("EndOfBuffer")
print("ns EndOfBuffer = " .. vim.inspect(eob))
assert(eob.bg == 0x21252b, "EndOfBuffer bg should match Normal bg")

print("ALL HIGHLIGHTS TESTS PASSED")
vim.cmd("qa!")
