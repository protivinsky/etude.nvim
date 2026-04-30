-- Drives a full session by simulating typing via nvim_buf_set_text.
--   nvim --headless -l spec/interactive_test.lua

local function step()
  vim.wait(20, function() return false end)
end

vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/etude.lua")

local etude = require("etude")
local data_path = vim.fn.tempname() .. ".etude.json"
etude.setup({ width = 60, line_count = 3, data_file = data_path })

-- Build a tiny fixed source so we know exactly what to type.
local path = vim.fn.tempname() .. ".txt"
local f = io.open(path, "w"); f:write("alpha bravo charlie\ndelta echo foxtrot\ngolf hotel india\n"); f:close()
require("etude.config").setup({
  width = 60, line_count = 3, data_file = data_path,
  sources = { { path = path, name = "test-text" } },
})

local sources = require("etude.source").list_all()
local file_src
for _, s in ipairs(sources) do
  if s.kind == "file" then file_src = s; break end
end
assert(file_src, "no file source found")

local runner = require("etude.runner")
runner.start(file_src)
local s = runner.get_active()
assert(s, "no active session")
print("expected lines:")
for i, l in ipairs(s.expected_lines) do print("  [" .. i .. "] " .. l) end

-- Simulate the user pressing `i` then typing the expected text.
vim.api.nvim_set_current_win(s.win)
vim.api.nvim_win_set_cursor(s.win, { s.words_row, 2 })
vim.cmd("startinsert")

-- Pretend each line is typed correctly (with one deliberate typo on line 2).
local PAD = 2
for i, expected in ipairs(s.expected_lines) do
  local typed = expected
  if i == 2 then
    typed = expected:sub(1, 1) .. "X" .. expected:sub(3)
  end
  local row0 = s.words_row - 1 + (i - 1) -- 0-based buffer row
  vim.bo[s.buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.buf, row0, row0 + 1, false, { string.rep(" ", PAD) .. typed })
  vim.bo[s.buf].modifiable = false
  -- Move the cursor to the end of the row so on_buffer_change can detect end-of-line.
  vim.api.nvim_win_set_cursor(s.win, { s.words_row + i - 1, PAD + #typed })
  step()
end

-- Wait briefly for the finish callback to land.
vim.wait(300, function() return s.finished end)
assert(s.finished, "session never finished")
print("OK session finished, secs=" .. s.secs)

-- Verify a run was recorded.
local data = require("etude.data").load(data_path)
assert(data.lifetime.runs == 1, "expected 1 lifetime run, got " .. data.lifetime.runs)
assert(#data.recent == 1, "expected 1 recent run")
print(("OK recorded: wpm=%d acc=%d chars=%d"):format(data.recent[1].wpm, data.recent[1].accuracy, data.recent[1].chars))

-- Bookmark advanced for the file source.
local prog = data.sources[path]
assert(prog and prog.byte_offset > 0, "bookmark did not advance")
print("OK bookmark advanced to byte " .. prog.byte_offset)

runner.close(s)
os.remove(path)
os.remove(data_path)
print("ALL INTERACTIVE TESTS PASSED")
vim.cmd("qa!")
