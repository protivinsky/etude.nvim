-- A small read-only float showing lifetime averages and the last 5 runs.

local M = {}

local data_mod = require("etude.data")
local config = require("etude.config")
local highlights = require("etude.highlights")

local api = vim.api

---@param ts integer
local function fmt_ts(ts)
  if ts == 0 then return "" end
  return os.date("%Y-%m-%d %H:%M", ts) --[[@as string]]
end

---@param secs number
local function fmt_secs(secs)
  if secs < 60 then return string.format("%ds", secs) end
  return string.format("%dm %ds", math.floor(secs / 60), math.floor(secs % 60))
end

local function build_lines(data)
  local wpm_avg, acc_avg = data_mod.averages(data)
  local lines = {}

  table.insert(lines, "")
  table.insert(lines, "  Lifetime")
  table.insert(lines, string.format("    runs:      %d", data.lifetime.runs))
  table.insert(lines, string.format("    avg wpm:   %d", wpm_avg))
  table.insert(lines, string.format("    avg acc:   %d%%", acc_avg))
  table.insert(lines, string.format("    practiced: %s", fmt_secs(data.lifetime.total_secs)))
  table.insert(lines, "")
  table.insert(lines, "  Last 5 runs")
  if #data.recent == 0 then
    table.insert(lines, "    (none yet)")
  else
    table.insert(lines, "    when                source                wpm   acc   time")
    for _, r in ipairs(data.recent) do
      local name = (r.source_name or r.source_id or "?")
      if #name > 20 then name = name:sub(1, 19) .. "…" end
      table.insert(lines, string.format(
        "    %-18s  %-20s  %3d   %3d%%  %s",
        fmt_ts(r.ts), name, r.wpm, r.accuracy, fmt_secs(r.duration_secs)
      ))
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  q/Esc to close")

  return lines
end

function M.open()
  local data = data_mod.load(config.values.data_file)
  local lines = build_lines(data)

  local width = 70
  for _, l in ipairs(lines) do
    if #l + 2 > width then width = #l + 2 end
  end
  local height = #lines

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "etude-stats"
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true

  local ns = api.nvim_create_namespace("etude-stats")
  highlights.setup(ns)

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " etude — stats ",
    title_pos = "center",
    zindex = 100,
  })
  api.nvim_win_set_hl_ns(win, ns)

  -- Highlight headings (rows starting with two spaces + capital letter)
  for i, l in ipairs(lines) do
    if l:match("^  %u") then
      api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
        end_col = #l,
        hl_group = "EtudeHeader",
      })
    end
  end

  vim.keymap.set("n", "q", function() pcall(api.nvim_win_close, win, true) end, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", function() pcall(api.nvim_win_close, win, true) end, { buffer = buf, silent = true })
end

return M
