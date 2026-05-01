-- Verify prev_chunk steps the bookmark backwards (file sources only).
--   nvim --headless -l spec/prev_chunk_test.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/etude.lua")

local data_path = vim.fn.tempname() .. ".etude.json"
local text_path = vim.fn.tempname() .. ".txt"
local body = ("alpha bravo charlie delta echo foxtrot "):rep(20) -- ~750 bytes
local f = io.open(text_path, "w"); f:write(body); f:close()

require("etude").setup({
  width = 30, line_count = 3, data_file = data_path,
  sources = { { path = text_path, name = "wordlist" } },
})

local sources = require("etude.source").list_all()
local file_src
for _, s in ipairs(sources) do if s.kind == "file" then file_src = s end end

local runner = require("etude.runner")

-- Advance forward, then back. Final offset should be < first advance offset.
runner.start(file_src)
local s = runner.get_active()
local off0 = s.start_byte_offset
print("session start offset = " .. off0)
assert(off0 == 0, "expected to start at 0, got " .. off0)

runner.next_chunk(s)
local off1 = s.start_byte_offset
print("after next_chunk      = " .. off1)
assert(off1 > off0, "next_chunk should advance offset")

runner.next_chunk(s)
local off2 = s.start_byte_offset
print("after next_chunk x2   = " .. off2)
assert(off2 > off1, "second next_chunk should advance further")

runner.prev_chunk(s)
local off3 = s.start_byte_offset
print("after prev_chunk      = " .. off3)
assert(off3 < off2, "prev_chunk should rewind from " .. off2 .. " (got " .. off3 .. ")")

-- Bookmark in data should match.
local data = require("etude.data").load(data_path)
local prog = data.sources[text_path]
assert(prog.byte_offset == off3, "saved bookmark should match session offset")

-- prev_chunk at offset 0 is a no-op (no error).
while s.start_byte_offset > 0 do
  runner.prev_chunk(s)
end
assert(s.start_byte_offset == 0, "expected to be at 0")
runner.prev_chunk(s) -- should not error
assert(s.start_byte_offset == 0, "prev_chunk at 0 should be a no-op")
print("OK prev_chunk at start of file is a no-op")

-- prev_chunk on a built-in source is a no-op (with a notify).
runner.close(s)
local random_src
for _, src in ipairs(sources) do
  if src.id == "builtin:random_common" then random_src = src end
end
runner.start(random_src)
s = runner.get_active()
local before = s.start_byte_offset
runner.prev_chunk(s)
assert(s.start_byte_offset == before, "prev_chunk on random source should not change offset")
print("OK prev_chunk on built-in source is a no-op")

runner.close(s)
os.remove(text_path)
os.remove(data_path)
print("ALL PREV-CHUNK TESTS PASSED")
vim.cmd("qa!")
