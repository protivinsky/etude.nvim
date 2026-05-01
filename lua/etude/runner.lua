-- The runner owns one practice session: float window, buffer, extmarks,
-- timer, keymaps. All session state is captured as upvalues here -- nothing
-- module-level mutates between sessions.

local M = {}

local config = require("etude.config")
local highlights = require("etude.highlights")
local source_mod = require("etude.source")
local data_mod = require("etude.data")

local api = vim.api
local PAD = 2 -- horizontal padding inside the float

-- Module-singleton handle to the *currently open* session, so :Etude
-- reopen-while-open is a no-op rather than stacking floats.
---@type etude.Session?
local active = nil

---@class etude.Session
---@field source etude.Source
---@field expected_lines string[]
---@field line_count integer
---@field width integer
---@field buf integer
---@field win integer
---@field ns integer
---@field words_row integer       -- 1-based row index where typing area starts
---@field start_byte_offset integer
---@field advance integer         -- bytes the current chunk consumed (file source)
---@field timer userdata          -- vim.uv timer
---@field secs integer
---@field started boolean
---@field finished boolean
---@field mode_change_au integer    -- ModeChanged autocmd id
---@field insert_enter_au integer   -- InsertEnter autocmd id (timer trigger)
---@field winclosed_au integer

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Indexing convention:
--   s.words_row is 1-based (used directly by nvim_win_set_cursor).
--   For 0-based buffer/extmark APIs, use (s.words_row - 1).

---@param s etude.Session
---@param idx integer  1-based line index within expected_lines
---@return integer     0-based buffer row for that typing line
local function row0(s, idx)
  return s.words_row - 1 + (idx - 1)
end

---@param s etude.Session
local function pending_virt(s)
  -- For each expected line, an extmark with virt_text covering the visible chars.
  for i, line in ipairs(s.expected_lines) do
    api.nvim_buf_set_extmark(s.buf, s.ns, row0(s, i), 0, {
      id = i,
      virt_text = { { line, "EtudePending" } },
      virt_text_win_col = PAD,
    })
  end
end

---@param expected string
---@param typed string
---@return {[1]: string, [2]: string}[]
local function build_diff_chunks(expected, typed)
  -- Greedy run-length grouping by status -- expected vs. typed, char by char.
  --
  -- Display rules:
  --   - untyped position: show the expected char in pending color (gray).
  --   - typed correctly:  show the (matching) char in correct color (green).
  --   - typed wrong:      show what the user actually typed in wrong color (red).
  --                       If they typed a space where a non-space was expected,
  --                       render an underscore so the wrong-space is visible.
  local chunks = {}
  local n_typed = #typed
  local last_status = nil

  for i = 1, #expected do
    local exp = expected:sub(i, i)
    local got = typed:sub(i, i)
    local status, display

    if i > n_typed then
      status, display = "EtudePending", exp
    elseif got == exp then
      status, display = "EtudeCorrect", exp
    else
      if got == " " then
        status, display = "EtudeWrongSpace", "_"
      else
        status, display = "EtudeWrong", got
      end
    end

    local last = chunks[#chunks]
    if last and last_status == status then
      last[1] = last[1] .. display
    else
      table.insert(chunks, { display, status })
      last_status = status
    end
  end

  return chunks
end

---@param s etude.Session
---@param row_idx integer  1-based logical row index (in expected_lines)
---@param typed string
local function refresh_row(s, row_idx, typed)
  local expected = s.expected_lines[row_idx]
  if not expected then
    return
  end
  local chunks = build_diff_chunks(expected, typed)
  api.nvim_buf_set_extmark(s.buf, s.ns, row0(s, row_idx), 0, {
    id = row_idx,
    virt_text = chunks,
    virt_text_win_col = PAD,
  })
end

---@param s etude.Session
local function set_canvas(s)
  -- Layout (1-based row numbers):
  --   1..(words_row-1)                        -> header rows (empty; header
  --                                              renders via extmark on row 1)
  --   words_row..(words_row+line_count-1)     -> typing rows (PAD spaces; the
  --                                              user types after them with
  --                                              virtualedit=all)
  --   ... + 1 blank ...                       -> spacer
  --   ... + 2 footer ...                      -> stats + key hints (extmarks)
  local total = (s.words_row - 1) + s.line_count + 1 + 2
  local pad_str = string.rep(" ", PAD)
  local lines = {}
  for i = 1, total do
    if i >= s.words_row and i < s.words_row + s.line_count then
      table.insert(lines, pad_str)
    else
      table.insert(lines, "")
    end
  end
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
end

-- ---------------------------------------------------------------------------
-- Header / footer rendering (extmarks on dedicated rows)
-- ---------------------------------------------------------------------------

-- For file sources, include the progress percentage so users see how far
-- through the source they are. Built-in random/phrases sources just show
-- the name. The middle dot mirrors the previous in-title format.
---@param s etude.Session
---@return string
local function format_source_label(s)
  if s.source.kind == "file" and s.source.path then
    local stat = vim.uv.fs_stat(s.source.path)
    if stat and stat.size > 0 then
      local pct = math.floor((s.start_byte_offset / stat.size) * 100)
      return string.format(" %s · %d%% ", s.source.name, pct)
    end
  end
  return " " .. (s.source.name or "Practice") .. " "
end

---@param s etude.Session
local function render_header(s)
  -- Row 1: source label (left) + line-count selector (right)
  local left = format_source_label(s)

  -- Use virt_text on row 0 directly.
  local chunks = {
    { left, "EtudeHeader" },
  }
  -- Use display width (not byte length) so multi-byte chars in the label
  -- (e.g. the · separator) don't push the right-aligned section too far left.
  local used = vim.api.nvim_strwidth(left)
  local right_chunks = { { "Lines ", "EtudeMuted" } }
  local right_len = 6
  for i, n in ipairs({ 3, 6, 9 }) do
    if i > 1 then
      table.insert(right_chunks, { " ", "EtudeMuted" })
      right_len = right_len + 1
    end
    table.insert(right_chunks, { tostring(n), s.line_count == n and "EtudeKeyActive" or "EtudeKey" })
    right_len = right_len + 1
  end
  -- Mirror the leading PAD on the right so the line-count digits don't hug
  -- the border. (Two PADs total: one for the left, one for the right.)
  local pad = s.width - used - right_len - PAD * 2
  if pad < 1 then
    pad = 1
  end
  table.insert(chunks, { string.rep(" ", pad), "Normal" })
  for _, c in ipairs(right_chunks) do
    table.insert(chunks, c)
  end

  api.nvim_buf_set_extmark(s.buf, s.ns, 0, 0, {
    id = 1000,
    virt_text = chunks,
    virt_text_win_col = PAD,
  })
end

---@param s etude.Session
---@return string  Typed text on row `idx` (1-based), with leading PAD removed.
local function read_typed(s, idx)
  local lines = api.nvim_buf_get_lines(s.buf, row0(s, idx), row0(s, idx) + 1, false)
  local line = lines[1] or ""
  if #line <= PAD then return "" end
  return line:sub(PAD + 1)
end

---@param expected string
---@param typed string
---@return integer typed_count, integer correct_count
local function score_line(expected, typed)
  local n = math.min(#typed, #expected)
  local correct = 0
  for j = 1, n do
    if typed:sub(j, j) == expected:sub(j, j) then
      correct = correct + 1
    end
  end
  return n, correct
end

---@param s etude.Session
local function render_footer(s)
  -- Footer rows: stats line right after a blank spacer, hints on the next row.
  local stats_row0 = (s.words_row - 1) + s.line_count + 1
  local hints_row0 = stats_row0 + 1

  local typed_chars, correct = 0, 0
  for i, expected in ipairs(s.expected_lines) do
    local typed = read_typed(s, i)
    local n, c = score_line(expected, typed)
    typed_chars = typed_chars + n
    correct = correct + c
  end

  local secs = math.max(s.secs, 1)
  local wpm = math.floor((correct / 5) / (secs / 60))
  local accuracy = typed_chars > 0 and math.floor((correct / typed_chars) * 100) or 100

  local time_str = string.format("%ds", s.secs)
  local wpm_str = string.format("%d wpm", wpm)
  local acc_str = string.format("%d%% acc", accuracy)

  local chunks = {
    { time_str, "EtudeAccent" },
    { "  ", "Normal" },
    { wpm_str, "EtudeAccent" },
    { "  ", "Normal" },
    { acc_str, "EtudeAccent" },
  }

  api.nvim_buf_set_extmark(s.buf, s.ns, stats_row0, 0, {
    id = 1001,
    virt_text = chunks,
    virt_text_win_col = PAD,
  })

  -- Mappings hint, one row below
  local hints = {
    { " i ", "EtudeKey" }, { " start  ", "EtudeMuted" },
    { " <Esc> ", "EtudeKey" }, { " stop  ", "EtudeMuted" },
    { " <C-r> ", "EtudeKey" }, { " restart  ", "EtudeMuted" },
    { " <C-p> ", "EtudeKey" }, { " prev  ", "EtudeMuted" },
    { " <C-n> ", "EtudeKey" }, { " next  ", "EtudeMuted" },
    { " q ", "EtudeKey" }, { " quit", "EtudeMuted" },
  }
  api.nvim_buf_set_extmark(s.buf, s.ns, hints_row0, 0, {
    id = 1002,
    virt_text = hints,
    virt_text_win_col = PAD,
  })
end

---@param s etude.Session
local function redraw_all(s)
  pending_virt(s)
  render_header(s)
  render_footer(s)
end

-- ---------------------------------------------------------------------------
-- Finishing & stats
-- ---------------------------------------------------------------------------

---@param s etude.Session
local function compute_run(s)
  local total, typed_total, correct = 0, 0, 0
  for i, expected in ipairs(s.expected_lines) do
    local typed = read_typed(s, i)
    local n, c = score_line(expected, typed)
    total = total + #expected
    typed_total = typed_total + n
    correct = correct + c
  end
  local secs = math.max(s.secs, 1)
  local wpm = math.floor((correct / 5) / (secs / 60))
  local accuracy = typed_total > 0 and math.floor((correct / typed_total) * 100) or 0
  return {
    wpm = wpm,
    accuracy = accuracy,
    duration_secs = s.secs,
    chars = total,
  }
end

---@param s etude.Session
local function finish(s)
  if s.finished then
    return
  end
  s.finished = true
  s.timer:stop()
  vim.cmd.stopinsert()

  local run = compute_run(s)
  local data = data_mod.load(config.values.data_file)
  data_mod.record_run(data, {
    ts = os.time(),
    source_id = s.source.id,
    source_name = s.source.name,
    wpm = run.wpm,
    accuracy = run.accuracy,
    duration_secs = run.duration_secs,
    chars = run.chars,
  })
  if s.source.kind == "file" and s.source.path then
    local prog = data_mod.get_progress(data, s.source.path)
    prog.byte_offset = s.start_byte_offset + s.advance
    prog.last_used = os.time()
  end
  data_mod.save(config.values.data_file, data)

  -- Show a compact result badge in the footer
  local stats_row0 = (s.words_row - 1) + s.line_count + 1
  api.nvim_buf_set_extmark(s.buf, s.ns, stats_row0, 0, {
    id = 1001,
    virt_text = {
      { " done  ", "EtudeCorrect" },
      { string.format("%d wpm  ", run.wpm), "EtudeAccent" },
      { string.format("%d%% acc  ", run.accuracy), "EtudeAccent" },
      { string.format("%ds", s.secs), "EtudeMuted" },
    },
    virt_text_win_col = PAD,
  })
end

-- ---------------------------------------------------------------------------
-- Cursor / chunk advance handling
-- ---------------------------------------------------------------------------

---@param s etude.Session
local function on_buffer_change(s)
  if s.finished then
    return
  end
  -- Note: the timer is started on InsertEnter (set up in start()), not here.
  -- Buffer changes happen for both real typing and programmatic writes
  -- (set_canvas after restart / next_chunk), so we can't use them to gate
  -- the test clock.

  local pos = api.nvim_win_get_cursor(s.win)
  local row = pos[1] -- 1-based
  local row_idx = row - s.words_row + 1
  if row_idx < 1 or row_idx > s.line_count then
    return
  end

  local typed = read_typed(s, row_idx)
  local expected = s.expected_lines[row_idx] or ""
  if #typed > #expected then
    typed = typed:sub(1, #expected)
  end
  refresh_row(s, row_idx, typed)
  render_footer(s)

  -- If user has typed the whole expected line, advance to the next row (or
  -- finish). Use `#s.expected_lines` rather than `s.line_count` so a chunk
  -- shorter than the configured number of rows (e.g., the tail of a file
  -- source) ends correctly.
  if #typed >= #expected then
    if row_idx >= #s.expected_lines then
      finish(s)
    else
      vim.schedule(function()
        if api.nvim_win_is_valid(s.win) then
          api.nvim_win_set_cursor(s.win, { row + 1, PAD })
        end
      end)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------

---@param s etude.Session
local function set_keymaps(s)
  local opts = { buffer = s.buf, silent = true, nowait = true }
  local map = vim.keymap.set

  map("n", "i", function()
    api.nvim_win_set_cursor(s.win, { s.words_row, PAD })
    vim.cmd.startinsert()
  end, opts)

  map("n", "q", function() M.close(s) end, opts)
  map("n", "<Esc>", function() M.close(s) end, opts)

  map("n", "<C-r>", function() M.restart(s) end, opts)
  map("n", "<C-n>", function() M.next_chunk(s) end, opts)
  map("n", "<C-p>", function() M.prev_chunk(s) end, opts)

  for _, n in ipairs({ 3, 6, 9 }) do
    map("n", tostring(n), function() M.set_line_count(s, n) end, opts)
  end

  -- Block normal-mode operators that would shred the canvas. Insert mode
  -- changes are gated by the buffer being only modifiable in insert mode.
  for _, k in ipairs({ "o", "O", "p", "P", "dd", "cc", "x", "X", "D", "C", "J" }) do
    map("n", k, "<Nop>", opts)
  end
  -- Block carriage returns inside insert (don't let users insert a newline).
  map("i", "<CR>", "<Nop>", opts)
  map("i", "<C-m>", "<Nop>", opts)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

---@param s etude.Session
function M.close(s)
  if active ~= s then return end
  active = nil

  pcall(function() s.timer:stop() end)
  pcall(function() s.timer:close() end)

  if s.mode_change_au and s.mode_change_au > 0 then
    pcall(api.nvim_del_autocmd, s.mode_change_au)
  end
  if s.insert_enter_au and s.insert_enter_au > 0 then
    pcall(api.nvim_del_autocmd, s.insert_enter_au)
  end
  if s.winclosed_au and s.winclosed_au > 0 then
    pcall(api.nvim_del_autocmd, s.winclosed_au)
  end
  if api.nvim_win_is_valid(s.win) then
    pcall(api.nvim_win_close, s.win, true)
  end
  if api.nvim_buf_is_valid(s.buf) then
    pcall(api.nvim_buf_delete, s.buf, { force = true })
  end
end

---@param s etude.Session
function M.restart(s)
  -- Re-render existing chunk from scratch. Mode is preserved -- the user
  -- presses `i` to start typing again, just like at session start.
  s.secs = 0
  s.started = false
  s.finished = false
  s.timer:stop()
  set_canvas(s)
  redraw_all(s)
  api.nvim_win_set_cursor(s.win, { s.words_row, PAD })
  if api.nvim_get_mode().mode == "i" then
    vim.cmd.stopinsert()
  end
end

---@param s etude.Session
function M.next_chunk(s)
  local data = data_mod.load(config.values.data_file)
  if s.source.kind == "file" and s.source.path then
    local prog = data_mod.get_progress(data, s.source.path)
    prog.byte_offset = s.start_byte_offset + s.advance
    prog.last_used = os.time()
    data_mod.save(config.values.data_file, data)
    s.start_byte_offset = prog.byte_offset
  end
  local chunk = source_mod.chunk(s.source, s.start_byte_offset, s.width - PAD * 2, s.line_count)
  if not chunk or #chunk.lines == 0 then
    vim.notify("etude: no more text in this source", vim.log.levels.INFO)
    return
  end
  s.expected_lines = chunk.lines
  s.advance = chunk.advance
  -- M.restart triggers redraw_all -> render_header, which picks up the new
  -- start_byte_offset and shows the updated progress percentage.
  M.restart(s)
end

---Step backwards by approximately one chunk. Only meaningful for file
---sources -- random/phrases generate fresh content per chunk so "previous"
---has no stable referent.
---@param s etude.Session
function M.prev_chunk(s)
  if s.source.kind ~= "file" or not s.source.path then
    vim.notify("etude: previous chunk is only available for file sources", vim.log.levels.INFO)
    return
  end
  if s.start_byte_offset == 0 then
    vim.notify("etude: already at the start of this source", vim.log.levels.INFO)
    return
  end

  -- Chunks aren't exactly symmetric (wrap points depend on width and word
  -- boundaries, and normalization may shift offsets), so step back by the
  -- current chunk's advance as a best-effort approximation.
  local step = math.max(s.advance, 1)
  local target = math.max(0, s.start_byte_offset - step)

  local data = data_mod.load(config.values.data_file)
  local prog = data_mod.get_progress(data, s.source.path)
  prog.byte_offset = target
  prog.last_used = os.time()
  data_mod.save(config.values.data_file, data)
  s.start_byte_offset = target

  local chunk = source_mod.chunk(s.source, target, s.width - PAD * 2, s.line_count)
  if not chunk or #chunk.lines == 0 then
    vim.notify("etude: no text at the previous position", vim.log.levels.WARN)
    return
  end
  s.expected_lines = chunk.lines
  s.advance = chunk.advance
  M.restart(s)
end

---@param s etude.Session
---@param n integer
function M.set_line_count(s, n)
  if n == s.line_count then return end
  s.line_count = n
  -- Resize the float vertically (matches the layout in start()/set_canvas).
  local total = (s.words_row - 1) + n + 1 + 2
  api.nvim_win_set_height(s.win, total)
  -- Re-fetch a chunk of the new size from the same offset (file source
  -- bookmark is unchanged because this is a reset, not an advance).
  local chunk = source_mod.chunk(s.source, s.start_byte_offset, s.width - PAD * 2, n)
  if chunk and #chunk.lines > 0 then
    s.expected_lines = chunk.lines
    s.advance = chunk.advance
  end
  -- Persist as the global default for future sessions.
  local data = data_mod.load(config.values.data_file)
  data.prefs.line_count = n
  data_mod.save(config.values.data_file, data)
  M.restart(s)
end

-- ---------------------------------------------------------------------------
-- Public entry: start a session for a given source.
-- ---------------------------------------------------------------------------

---@param source etude.Source
function M.start(source)
  if active then
    -- Reuse the open session if the user re-runs :Etude.
    api.nvim_set_current_win(active.win)
    return
  end

  local cfg = config.values
  local width = cfg.width
  local content_w = width - PAD * 2

  -- Load data once and pull both the session-restoring prefs (line count)
  -- and the per-source bookmark from it.
  local data = data_mod.load(cfg.data_file)
  local line_count = data.prefs.line_count or cfg.line_count

  local start_offset = 0
  if source.kind == "file" and source.path then
    start_offset = data_mod.get_progress(data, source.path).byte_offset
  end

  local chunk = source_mod.chunk(source, start_offset, content_w, line_count)
  if not chunk or #chunk.lines == 0 then
    -- File exhausted -- wrap to start.
    if source.kind == "file" then
      start_offset = 0
      chunk = source_mod.chunk(source, 0, content_w, line_count)
    end
    if not chunk or #chunk.lines == 0 then
      vim.notify("etude: source has no usable text: " .. (source.name or source.id), vim.log.levels.WARN)
      return
    end
  end

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "etude"
  -- Silence built-in insert-mode completion (i_CTRL-N / i_CTRL-P / omnifunc).
  -- Third-party completion plugins (nvim-cmp, blink.cmp, coq, ...) don't
  -- read these options -- disable those in your completion config keyed on
  -- `vim.bo.filetype == "etude"`. See doc/etude.txt for recipes.
  vim.bo[buf].complete = ""
  vim.bo[buf].omnifunc = ""

  -- Layout: 1 header row + 1 blank spacer, N typing rows, 1 blank spacer,
  --         2 footer rows (stats + key hints). One blank above, one below
  --         the typing area, for symmetric breathing room.
  local words_row_idx = 3
  local total_h = (words_row_idx - 1) + line_count + 1 + 2

  local ns = api.nvim_create_namespace("etude")
  highlights.setup(ns)

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = total_h,
    row = math.max(0, math.floor((vim.o.lines - total_h) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " etude ",
    title_pos = "center",
    zindex = 100,
  })
  api.nvim_win_set_hl_ns(win, ns)
  vim.wo[win].wrap = false
  vim.wo[win].sidescrolloff = 0
  vim.wo[win].virtualedit = "all"

  ---@type etude.Session
  local s = {
    source = source,
    expected_lines = chunk.lines,
    line_count = line_count,
    width = width,
    buf = buf,
    win = win,
    ns = ns,
    words_row = words_row_idx,
    start_byte_offset = start_offset,
    advance = chunk.advance,
    timer = vim.uv.new_timer(),
    secs = 0,
    started = false,
    finished = false,
    mode_change_au = 0,
    insert_enter_au = 0,
    winclosed_au = 0,
  }
  active = s

  set_canvas(s)
  redraw_all(s)
  set_keymaps(s)

  -- Buffer is locked outside insert mode -- prevents normal-mode edits
  -- from corrupting the canvas. Toggled on InsertEnter/InsertLeave.
  vim.bo[buf].modifiable = false
  s.mode_change_au = api.nvim_create_autocmd("ModeChanged", {
    buffer = buf,
    callback = function(ev)
      if not api.nvim_buf_is_valid(buf) then return end
      local _, new = ev.match:match("([^:]+):([^:]+)")
      if new == "i" then
        vim.bo[buf].modifiable = true
      else
        vim.bo[buf].modifiable = false
      end
    end,
  })

  -- The test clock starts the first time the user enters insert mode.
  -- (Re)entering insert after a restart / <C-n> is treated as the start of
  -- the new run, since restart() clears `started` to false.
  s.insert_enter_au = api.nvim_create_autocmd("InsertEnter", {
    buffer = buf,
    callback = function()
      if s.finished or s.started then return end
      s.started = true
      s.timer:start(0, 1000, vim.schedule_wrap(function()
        if not api.nvim_buf_is_valid(s.buf) or s.finished then
          return
        end
        s.secs = s.secs + 1
        render_footer(s)
      end))
    end,
  })

  s.winclosed_au = api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    callback = function() M.close(s) end,
  })

  -- Track typing -- on_lines fires for every keystroke that changes the buffer.
  api.nvim_buf_attach(buf, false, {
    on_lines = function()
      vim.schedule(function()
        if api.nvim_buf_is_valid(buf) and active == s then
          on_buffer_change(s)
        end
      end)
    end,
    on_detach = function()
      if active == s then
        active = nil
      end
    end,
  })

  api.nvim_win_set_cursor(win, { words_row_idx, PAD })

  if type(cfg.on_attach) == "function" then
    pcall(cfg.on_attach, buf)
  end
end

---@return etude.Session?
function M.get_active()
  return active
end

return M
