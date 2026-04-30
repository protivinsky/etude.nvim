-- Verify the test clock starts on InsertEnter, not on session open or
-- programmatic buffer changes (set_canvas after restart / next_chunk).
--   nvim --headless -l spec/timer_test.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/etude.lua")

require("etude").setup({ width = 60, line_count = 3 })

local sources = require("etude.source").list_all()
local random_src
for _, s in ipairs(sources) do
  if s.id == "builtin:random_common" then random_src = s end
end

local runner = require("etude.runner")
runner.start(random_src)
local s = runner.get_active()

-- 1. Just opening shouldn't start the timer.
assert(not s.started, "timer should not have started on session open")
assert(s.secs == 0, "secs should be 0 at start")
print("OK session open: started=false")

-- 2. Calling restart (via set_line_count) shouldn't start the timer either,
--    even though set_canvas writes to the buffer (which used to trigger it).
runner.set_line_count(s, 6)
vim.wait(50) -- let any pending schedules drain
assert(not s.started, "set_line_count should not start the timer")
print("OK set_line_count: started=false")

-- 3. next_chunk also shouldn't start the timer.
runner.next_chunk(s)
vim.wait(50)
assert(not s.started, "next_chunk should not start the timer")
print("OK next_chunk: started=false")

-- 4. Triggering InsertEnter should start the timer. In headless mode without
--    a real UI, `:startinsert` doesn't reliably fire InsertEnter, so we
--    dispatch the event explicitly. The autocmd we registered listens to the
--    same event, so this is a faithful test of the trigger.
vim.api.nvim_exec_autocmds("InsertEnter", { buffer = s.buf })
vim.wait(20)
assert(s.started, "InsertEnter should have started the timer")
print("OK InsertEnter: started=true")

-- 5. Restart resets `started` so the timer can start fresh on the next
--    InsertEnter.
runner.restart(s)
vim.wait(50)
assert(not s.started, "restart should reset started")
print("OK restart resets started")

vim.api.nvim_exec_autocmds("InsertEnter", { buffer = s.buf })
vim.wait(20)
assert(s.started, "second InsertEnter starts timer again")
print("OK second InsertEnter: started=true")

runner.close(s)
print("ALL TIMER TESTS PASSED")
vim.cmd("qa!")
