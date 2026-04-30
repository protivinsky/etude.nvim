-- Smoke test runner: nvim --headless -l spec/headless_test.lua

local ok, err = pcall(function()
  vim.opt.runtimepath:prepend(vim.fn.getcwd())

  -- 1. Plugin file should register :Etude
  vim.cmd("runtime plugin/etude.lua")
  assert(vim.fn.exists(":Etude") == 2, ":Etude command not registered")
  print("OK :Etude registered")

  -- 2. setup() works
  local etude = require("etude")
  etude.setup({
    width = 60,
    line_count = 3,
    data_file = vim.fn.tempname() .. ".etude.json",
  })
  print("OK setup() runs")

  -- 3. Source list returns built-ins
  local sources = require("etude.source").list_all()
  assert(#sources >= 3, "expected at least 3 built-in sources, got " .. #sources)
  print("OK source.list_all returns " .. #sources .. " sources")

  -- 4. Random chunk generation
  local chunk = require("etude.source").random_chunk(
    { numbers = false, symbols = false, random = false }, 60, 3
  )
  assert(#chunk.lines == 3, "expected 3 random lines, got " .. #chunk.lines)
  for _, l in ipairs(chunk.lines) do
    assert(#l <= 60, "line too long: " .. l)
  end
  print("OK random_chunk")

  -- 5. File chunk generation + bookmark advance
  local path = vim.fn.tempname() .. ".txt"
  local body = ("The quick brown fox jumps over the lazy dog. "):rep(20)
  local f = io.open(path, "w"); f:write(body); f:close()
  local first = require("etude.source").file_chunk(path, 0, 40, 3)
  assert(first and #first.lines == 3, "expected 3 file lines")
  assert(first.advance > 0, "advance must be positive")
  local second = require("etude.source").file_chunk(path, first.advance, 40, 3)
  assert(second.lines[1] ~= first.lines[1], "second chunk should differ from first")
  os.remove(path)
  print("OK file_chunk + advance")

  -- 6. Data persistence round-trip
  local data_mod = require("etude.data")
  local cfg = require("etude.config")
  local data = data_mod.load(cfg.values.data_file)
  data_mod.record_run(data, {
    ts = os.time(), source_id = "x", source_name = "x",
    wpm = 60, accuracy = 95, duration_secs = 30, chars = 150,
  })
  data_mod.save(cfg.values.data_file, data)
  local reloaded = data_mod.load(cfg.values.data_file)
  assert(reloaded.lifetime.runs == 1, "expected 1 run, got " .. reloaded.lifetime.runs)
  assert(#reloaded.recent == 1, "expected 1 recent")
  os.remove(cfg.values.data_file)
  print("OK data persistence")

  -- 7. runner.start() opens a window for built-in random source
  local random_source
  for _, s in ipairs(sources) do
    if s.id == "builtin:random_common" then random_source = s end
  end
  require("etude.runner").start(random_source)
  local active = require("etude.runner").get_active()
  assert(active, "runner.get_active() returned nil")
  assert(vim.api.nvim_win_is_valid(active.win), "runner window is invalid")
  assert(vim.api.nvim_buf_is_valid(active.buf), "runner buffer is invalid")
  assert(vim.bo[active.buf].filetype == "etude", "wrong filetype")
  assert(#active.expected_lines == 3, "expected 3 lines")
  print("OK runner.start opened a window with " .. #active.expected_lines .. " lines")

  -- 8. Set line count adjusts window
  require("etude.runner").set_line_count(active, 6)
  active = require("etude.runner").get_active()
  assert(active.line_count == 6, "line_count not updated")
  assert(#active.expected_lines == 6, "expected_lines not updated")
  print("OK set_line_count")

  -- 9. Close the runner cleanly
  require("etude.runner").close(active)
  assert(require("etude.runner").get_active() == nil, "runner did not clean up")
  print("OK runner.close")

  -- 10. resume() falls back to picker when no history (we just deleted data)
  --     We can't actually pump vim.ui.select interactively, but we can verify
  --     it doesn't error.
  vim.ui.select = function(_, _, on_choice)
    on_choice(nil) -- user cancelled
  end
  local ok2, err2 = pcall(etude.resume)
  assert(ok2, "resume errored: " .. tostring(err2))
  print("OK resume fallback to picker")

  -- 11. Health check runs without error
  require("etude.health").check()
  print("OK health.check")
end)

if not ok then
  io.stderr:write("FAIL: " .. tostring(err) .. "\n")
  vim.cmd("cquit 1")
end

print("ALL TESTS PASSED")
vim.cmd("qa!")
