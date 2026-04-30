-- Verify that closing the runner and reopening on the same file source
-- continues from the saved byte offset.
--   nvim --headless -l spec/resume_test.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/etude.lua")

local data_path = vim.fn.tempname() .. ".etude.json"
local text_path = vim.fn.tempname() .. ".txt"
local body = "alpha bravo charlie delta echo foxtrot golf hotel india juliet "
  .. "kilo lima mike november oscar papa quebec romeo sierra tango uniform "
  .. "victor whiskey xray yankee zulu and back to alpha bravo charlie delta "
  .. "echo foxtrot golf hotel india juliet kilo lima mike november oscar"
local f = io.open(text_path, "w"); f:write(body); f:close()

require("etude").setup({
  width = 30,
  line_count = 3,
  data_file = data_path,
  sources = { { path = text_path, name = "wordlist" } },
})

local source_mod = require("etude.source")
local sources = source_mod.list_all()
local file_src
for _, s in ipairs(sources) do
  if s.kind == "file" then file_src = s end
end

-- Session 1: open, capture the original first line, advance, close.
local runner = require("etude.runner")
runner.start(file_src)
local s1 = runner.get_active()
local original_first_line = s1.expected_lines[1]
print("session1 first line: " .. original_first_line)
runner.next_chunk(s1) -- mutates s1 in place
local advanced_offset = s1.start_byte_offset
print("after next_chunk, offset=" .. advanced_offset)
assert(advanced_offset > 0, "next_chunk did not advance bookmark")
runner.close(s1)

-- Session 2: open same source, should resume from saved offset.
runner.start(file_src)
local s2 = runner.get_active()
print("session2 first line: " .. s2.expected_lines[1])
assert(s2.start_byte_offset == advanced_offset, "session 2 did not resume from saved offset")
assert(original_first_line ~= s2.expected_lines[1], "session 2 should show different text than session 1's original")
print("OK resumed from offset " .. s2.start_byte_offset)
runner.close(s2)

-- Session 3: resume() should re-open the same source even though we never
-- actually finished a run. We need at least one finished run for resume to
-- work, so simulate one by running a finish.
local data = require("etude.data").load(data_path)
require("etude.data").record_run(data, {
  ts = os.time(), source_id = file_src.id, source_name = file_src.name,
  wpm = 50, accuracy = 95, duration_secs = 30, chars = 60,
})
require("etude.data").save(data_path, data)

require("etude").resume()
local s3 = runner.get_active()
assert(s3, "resume did not open a session")
assert(s3.source.id == file_src.id, "resume opened wrong source")
print("OK resume() re-opened: " .. s3.source.name)
runner.close(s3)

os.remove(text_path)
os.remove(data_path)
print("ALL RESUME TESTS PASSED")
vim.cmd("qa!")
