-- Verify build_diff_chunks: wrong characters now display what the user
-- actually typed (in red), not the expected character.
--   nvim --headless -l spec/diff_chunks_test.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/etude.lua")

require("etude").setup({ width = 60, line_count = 3 })

-- Open a session against the random source and replace its line with a
-- fixed string so we can predictably test typed scenarios.
local sources = require("etude.source").list_all()
local picked
for _, s in ipairs(sources) do
  if s.id == "builtin:random_common" then picked = s end
end
require("etude.runner").start(picked)
local s = require("etude.runner").get_active()
s.expected_lines = { "abcdef" }
require("etude.runner").set_line_count(s, 3)
s.expected_lines = { "abcdef" }

-- Helper: feed a typed string into row 1 (0-based row 3) and read the diff
-- extmark's virt_text. We simulate by writing the buffer line directly.
local PAD = 2
local function set_typed(typed)
  vim.bo[s.buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.buf, s.words_row - 1, s.words_row, false, { string.rep(" ", PAD) .. typed })
  vim.bo[s.buf].modifiable = false
end

local function read_virt(row_idx)
  local target = s.words_row - 1 + row_idx - 1
  local marks = vim.api.nvim_buf_get_extmarks(s.buf, s.ns, 0, -1, { details = true })
  for _, m in ipairs(marks) do
    local _id, row, _col, det = m[1], m[2], m[3], m[4]
    if row == target and det.virt_text then return det.virt_text end
  end
  return nil
end

-- Force a refresh with given typed text.
local function refresh_and_read(typed)
  set_typed(typed)
  vim.api.nvim_win_set_cursor(s.win, { s.words_row, PAD + #typed })
  -- Trigger our on_lines path by writing again (already triggered by
  -- set_typed actually). Yield so the schedule runs.
  vim.wait(60)
  return read_virt(1)
end

local function describe(virt)
  local out = {}
  for _, c in ipairs(virt) do
    table.insert(out, string.format("%q->%s", c[1], c[2]))
  end
  return "[" .. table.concat(out, ", ") .. "]"
end

local function find_chunk_with(virt, text)
  for _, c in ipairs(virt) do
    if c[1] == text then return c end
  end
  return nil
end

-- All cases use a typed string SHORTER than expected so on_buffer_change
-- doesn't trigger finish() between cases.

-- Case 1: type "abxd" (typo at pos 3, expected "c", got "x")
do
  local virt = refresh_and_read("abxd")
  print("typed=abxd -> " .. describe(virt))
  local wrong = find_chunk_with(virt, "x")
  assert(wrong, "expected an 'x' chunk for the typed-wrong char")
  assert(wrong[2] == "EtudeWrong", "wrong char should use EtudeWrong, got " .. wrong[2])
  -- The expected 'c' should not appear standalone (we replaced it with 'x').
  for _, c in ipairs(virt) do
    assert(c[1] ~= "c", "expected char 'c' should not be rendered when typed wrong")
  end
end

-- Case 2: type "abc" (3 correct, then 3 pending)
do
  local virt = refresh_and_read("abc")
  print("typed=abc  -> " .. describe(virt))
  local correct = find_chunk_with(virt, "abc")
  assert(correct and correct[2] == "EtudeCorrect", "correct prefix should be in EtudeCorrect")
  local pending = find_chunk_with(virt, "def")
  assert(pending and pending[2] == "EtudePending", "remainder should be EtudePending")
end

-- Case 3: type a space where a non-space was expected -- show "_"
do
  local virt = refresh_and_read("ab d") -- pos 3 typed " " expected "c"
  print("typed=ab d -> " .. describe(virt))
  local marker = find_chunk_with(virt, "_")
  assert(marker, "wrong-space should render as underscore marker")
  assert(marker[2] == "EtudeWrongSpace", "underscore should use EtudeWrongSpace")
end

require("etude.runner").close(s)
print("ALL DIFF-CHUNK TESTS PASSED")
vim.cmd("qa!")
