-- Verify that the float title is the static "etude" and the source label
-- (name + progress %) lives in the header row above the typing area.
--   nvim --headless -l spec/title_test.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/etude.lua")

local data_path = vim.fn.tempname() .. ".etude.json"
local text_path = vim.fn.tempname() .. ".txt"
-- 200-byte file so percentages are easy to predict.
local body = string.rep("abcdefghij ", 18) .. "ab" -- 18*11 + 2 = 200 bytes
local f = io.open(text_path, "w"); f:write(body); f:close()
assert(#body == 200, "test fixture should be 200 bytes, got " .. #body)

require("etude").setup({
  width = 60, line_count = 3, data_file = data_path,
  sources = { { path = text_path, name = "test-doc" } },
})

local sources = require("etude.source").list_all()
local file_src
for _, s in ipairs(sources) do if s.kind == "file" then file_src = s end end

local function get_header_text(s)
  local marks = vim.api.nvim_buf_get_extmarks(s.buf, s.ns, 0, -1, { details = true })
  for _, m in ipairs(marks) do
    if m[2] == 0 and m[4].virt_text then
      local txt = ""
      for _, c in ipairs(m[4].virt_text) do txt = txt .. c[1] end
      return txt
    end
  end
  return ""
end

local function get_title(s)
  local cfg = vim.api.nvim_win_get_config(s.win)
  if type(cfg.title) == "table" then return cfg.title[1][1] end
  return tostring(cfg.title)
end

local runner = require("etude.runner")

-- 1. Fresh file source: title is " etude ", header shows "test-doc · 0%".
runner.start(file_src)
local s = runner.get_active()
print("title  = " .. get_title(s))
print("header = " .. get_header_text(s))
assert(get_title(s):match("etude"), "title should be 'etude', got " .. get_title(s))
assert(not get_title(s):match("test%-doc"), "title should not contain source name")
assert(get_header_text(s):match("test%-doc"), "header should contain source name")
assert(get_header_text(s):match("0%%"), "header should show 0% for fresh source")

-- 2. Bookmark @100/200 -> header shows 50%.
runner.close(s)
local data = require("etude.data").load(data_path)
require("etude.data").get_progress(data, text_path).byte_offset = 100
require("etude.data").save(data_path, data)

runner.start(file_src)
s = runner.get_active()
print("header @50%% = " .. get_header_text(s))
assert(get_title(s):match("etude"), "title still 'etude'")
assert(get_header_text(s):match("50%%"), "header should show 50%, got " .. get_header_text(s))

-- 3. Built-in source: header shows just the name (no percentage).
runner.close(s)
local random_src
for _, src in ipairs(sources) do
  if src.id == "builtin:random_common" then random_src = src end
end
runner.start(random_src)
s = runner.get_active()
print("random header = " .. get_header_text(s))
assert(get_title(s):match("etude"), "title still 'etude'")
assert(get_header_text(s):match("Common words"), "header should show source name")
assert(not get_header_text(s):match("%%"), "built-in source has no percentage")

runner.close(s)
os.remove(text_path)
os.remove(data_path)
print("ALL TITLE TESTS PASSED")
vim.cmd("qa!")
