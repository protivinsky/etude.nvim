-- Render the runner UI in a real (headless) UI and dump the screen.
--   nvim --headless --clean -l spec/ui_snapshot.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/etude.lua")

require("etude").setup({ width = 70, line_count = 3 })

-- Pick the built-in phrases source so we get deterministic-ish content.
local sources = require("etude.source").list_all()
local target
for _, s in ipairs(sources) do
  if s.id == "builtin:phrases" then target = s end
end

require("etude.runner").start(target)
local s = require("etude.runner").get_active()
print("source = " .. s.source.name)
print("expected_lines = " .. #s.expected_lines)
for i, l in ipairs(s.expected_lines) do print(("  [%d] %s"):format(i, l)) end
print("buffer rows = " .. vim.api.nvim_buf_line_count(s.buf))
print("buffer:")
for i, line in ipairs(vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)) do
  print(("  %2d| %q"):format(i, line))
end
print("extmarks:")
local marks = vim.api.nvim_buf_get_extmarks(s.buf, s.ns, 0, -1, { details = true })
for _, m in ipairs(marks) do
  local _, row, _, det = unpack(m)
  if det.virt_text then
    local text = ""
    for _, c in ipairs(det.virt_text) do text = text .. c[1] end
    print(("  row=%d  -> %q"):format(row, text))
  end
end

vim.cmd("qa!")
