-- Smoke test for the stats float.
--   nvim --headless -l spec/stats_ui_test.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/etude.lua")

local data_path = vim.fn.tempname() .. ".etude.json"
require("etude").setup({ data_file = data_path })

-- Empty stats
require("etude").stats()
local first_buf = vim.api.nvim_get_current_buf()
local first_lines = vim.api.nvim_buf_get_lines(first_buf, 0, -1, false)
print("=== empty stats ===")
for _, l in ipairs(first_lines) do print(l) end
assert(vim.tbl_contains(first_lines, "    runs:      0"), "expected '0 runs' in empty stats")
assert(vim.tbl_contains(first_lines, "    (none yet)"), "expected '(none yet)' line")
vim.api.nvim_win_close(0, true)

-- Add a couple of runs
local data_mod = require("etude.data")
local data = data_mod.load(data_path)
for i = 1, 3 do
  data_mod.record_run(data, {
    ts = os.time() - (3 - i) * 100,
    source_id = "test:" .. i,
    source_name = "src" .. i,
    wpm = 50 + i * 10,
    accuracy = 90 + i,
    duration_secs = 30,
    chars = 150,
  })
end
data_mod.save(data_path, data)

require("etude").stats()
local second_buf = vim.api.nvim_get_current_buf()
local second_lines = vim.api.nvim_buf_get_lines(second_buf, 0, -1, false)
print("=== populated stats ===")
for _, l in ipairs(second_lines) do print(l) end
local has_3_runs = false
for _, l in ipairs(second_lines) do
  if l:find("runs:%s+3") then has_3_runs = true end
end
assert(has_3_runs, "expected 3 runs reflected in stats")

os.remove(data_path)
print("ALL STATS UI TESTS PASSED")
vim.cmd("qa!")
