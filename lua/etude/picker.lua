-- Source picker.
--
-- Uses vim.ui.select unconditionally. Picker plugins (snacks.picker,
-- telescope-ui-select, dressing.nvim, mini.pick, fzf-lua's ui_select)
-- override vim.ui.select transparently, so this gives us "common pickers"
-- support for free without hard-coding any of them.

local M = {}

local source_mod = require("etude.source")
local data_mod = require("etude.data")
local config = require("etude.config")
local runner = require("etude.runner")

local function format_progress(src, data)
  if src.kind ~= "file" or not src.path then
    return ""
  end
  local prog = data.sources[src.path]
  if not prog or prog.byte_offset == 0 then
    return "  (new)"
  end
  -- Try to compute %; fall back to byte offset if we can't stat.
  local stat = vim.uv.fs_stat(src.path)
  if stat and stat.size > 0 then
    local pct = math.floor((prog.byte_offset / stat.size) * 100)
    return string.format("  (%d%%)", pct)
  end
  return string.format("  (%d bytes)", prog.byte_offset)
end

function M.pick()
  local sources = source_mod.list_all()
  local data = data_mod.load(config.values.data_file)

  vim.ui.select(sources, {
    prompt = "Etude: choose practice source",
    format_item = function(s)
      return s.name .. format_progress(s, data)
    end,
    kind = "etude.source",
  }, function(choice)
    if not choice then return end
    runner.start(choice)
  end)
end

return M
