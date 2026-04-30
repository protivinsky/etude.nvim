---@class etude
local M = {}

local config = require("etude.config")

---@param opts etude.UserConfig?
function M.setup(opts)
  config.setup(opts)
end

---Open the source picker. With no setup() call, defaults apply.
function M.pick()
  require("etude.picker").pick()
end

---Resume the most recently practiced file source. Falls back to the picker
---if there is no history.
function M.resume()
  local data = require("etude.data").load(config.values.data_file)
  if #data.recent == 0 then
    return M.pick()
  end
  local last = data.recent[1]
  -- Find the matching source.
  for _, src in ipairs(require("etude.source").list_all()) do
    if src.id == last.source_id then
      require("etude.runner").start(src)
      return
    end
  end
  -- Source no longer configured -- fall back to the picker.
  M.pick()
end

---Show the stats float.
function M.stats()
  require("etude.stats_ui").open()
end

return M
