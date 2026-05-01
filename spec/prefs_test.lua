-- Verify line_count is persisted across sessions.
--   nvim --headless -l spec/prefs_test.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/etude.lua")

local data_path = vim.fn.tempname() .. ".etude.json"
require("etude").setup({ line_count = 3, data_file = data_path })

local sources = require("etude.source").list_all()
local random_src
for _, s in ipairs(sources) do
  if s.id == "builtin:random_common" then random_src = s end
end

local runner = require("etude.runner")

-- Session 1: starts with default 3, user switches to 6.
runner.start(random_src)
local s = runner.get_active()
assert(s.line_count == 3, "expected default 3, got " .. s.line_count)
print("session 1 default line_count = " .. s.line_count)

runner.set_line_count(s, 6)
assert(s.line_count == 6, "expected 6 after switch")
print("after set_line_count(6)      = " .. s.line_count)

local data = require("etude.data").load(data_path)
assert(data.prefs.line_count == 6, "data.prefs.line_count should be 6, got " .. tostring(data.prefs.line_count))
print("OK data.prefs.line_count persisted = " .. data.prefs.line_count)

runner.close(s)

-- Session 2: should restore 6, not the config default 3.
runner.start(random_src)
s = runner.get_active()
assert(s.line_count == 6, "session 2 should restore line_count=6, got " .. s.line_count)
print("session 2 restored line_count = " .. s.line_count)

-- Switch to 9 to make sure the override flow still works.
runner.set_line_count(s, 9)
assert(s.line_count == 9, "expected 9 after switch")
runner.close(s)

data = require("etude.data").load(data_path)
assert(data.prefs.line_count == 9, "should now be 9, got " .. tostring(data.prefs.line_count))
print("OK persisted final value     = " .. data.prefs.line_count)

os.remove(data_path)
print("ALL PREFS TESTS PASSED")
vim.cmd("qa!")
