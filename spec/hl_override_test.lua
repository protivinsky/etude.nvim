-- Verify that highlights config overrides take effect.
--   nvim --headless -l spec/hl_override_test.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/etude.lua")

-- Set Normal so the float-bg branch in highlights.setup runs.
vim.api.nvim_set_hl(0, "Normal", { fg = "#abb2bf", bg = "#21252b" })

require("etude").setup({
  highlights = {
    pending = "Conceal",                  -- string form: link
    correct = { fg = "#aaffaa", bold = true }, -- table form: full spec
    wrong   = { link = "ErrorMsg" },           -- table-with-link
  },
})

local ns = vim.api.nvim_create_namespace("etude")
require("etude.highlights").setup(ns)

local function ns_hl(name)
  return vim.api.nvim_get_hl(ns, { name = name, link = false })
end

local pending = ns_hl("EtudePending")
print("EtudePending = " .. vim.inspect(pending))
assert(pending.link == "Conceal", "pending should link to Conceal, got " .. vim.inspect(pending))

local correct = ns_hl("EtudeCorrect")
print("EtudeCorrect = " .. vim.inspect(correct))
assert(correct.fg == 0xaaffaa, "correct fg should be #aaffaa, got " .. tostring(correct.fg))
assert(correct.bold == true, "correct should be bold")

local wrong = ns_hl("EtudeWrong")
print("EtudeWrong = " .. vim.inspect(wrong))
assert(wrong.link == "ErrorMsg", "wrong should link to ErrorMsg, got " .. vim.inspect(wrong))

-- Unspecified groups keep their defaults.
local key = ns_hl("EtudeKey")
assert(key.link == "Special", "key should still default to Special, got " .. vim.inspect(key))

print("ALL HIGHLIGHT-OVERRIDE TESTS PASSED")
vim.cmd("qa!")
