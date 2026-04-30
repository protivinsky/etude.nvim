-- Verifies the text-normalization layer.
--   nvim --headless -l spec/normalize_test.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local text = require("etude.text")

local cases = {
  { "smart double quotes",       "He said \226\128\156hi\226\128\157",  'He said "hi"' },
  { "smart single quotes",       "it\226\128\153s a test",              "it's a test" },
  { "em dash",                   "well\226\128\148maybe",               "well--maybe" },
  { "en dash",                   "page 12\226\128\1473",                "page 12-3" },
  { "ellipsis",                  "wait\226\128\166",                    "wait..." },
  { "non-breaking space",        "a\194\160b",                          "a b" },
  { "CRLF -> LF -> space",       "line1\r\nline2",                      "line1 line2" },
  { "CR -> space",               "line1\rline2",                        "line1 line2" },
  { "double newline collapses",  "para1\n\npara2",                      "para1 para2" },
  { "tab -> space",              "a\tb",                                "a b" },
  { "non-ASCII dropped",         "caf\195\169 latte",                   "caf latte" },
  { "control chars dropped",     "hi\1\2\3 there",                      "hi there" },
  { "trim leading/trailing",     "   hello world   ",                   "hello world" },
  { "collapse multi-space",      "a    b",                              "a b" },
  { "empty input",               "",                                    "" },
  { "nil input",                 nil,                                   "" },
}

local failures = 0
for _, case in ipairs(cases) do
  local desc, input, expected = case[1], case[2], case[3]
  local got = text.normalize(input)
  if got == expected then
    print(("OK  %s"):format(desc))
  else
    failures = failures + 1
    print(("FAIL %s\n     input    = %q\n     expected = %q\n     got      = %q"):format(
      desc, tostring(input), expected, got))
  end
end

-- Round-trip with an actual file source.
require("etude").setup({})
local path = vim.fn.tempname() .. ".txt"
local f = io.open(path, "w")
-- "It\u{2019}s a \u{201C}beautiful\u{201D} day\u{2014}really." with CRLF.
f:write("It\226\128\153s a \226\128\156beautiful\226\128\157 day\226\128\148really.\r\n\r\nNext paragraph.")
f:close()

local source = require("etude.source")
local chunk = source.file_chunk(path, 0, 80, 1)
assert(chunk, "file_chunk returned nil")
local line = chunk.lines[1]
assert(line:find("'") ~= nil, "smart single quote not normalized: " .. line)
assert(line:find('"') ~= nil, "smart double quote not normalized: " .. line)
assert(line:find("--") ~= nil, "em dash not normalized: " .. line)
assert(line:find("\r") == nil, "CR not stripped: " .. line)
print("OK  end-to-end file_chunk normalization: " .. line)

-- normalize=false leaves bytes alone.
local raw_chunk = source.file_chunk(path, 0, 80, 1, false)
assert(raw_chunk, "raw file_chunk returned nil")
-- Need to read just the first line because raw text contains newlines.
local raw_text = table.concat(raw_chunk.lines, "")
assert(raw_text:find("\226\128\153") ~= nil, "raw mode should preserve smart quotes")
print("OK  normalize=false preserves raw bytes")

os.remove(path)

if failures > 0 then
  io.stderr:write(("\n%d failures\n"):format(failures))
  vim.cmd("cquit 1")
end
print("ALL NORMALIZATION TESTS PASSED")
vim.cmd("qa!")
