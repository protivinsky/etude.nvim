-- Persistence layer for etude.nvim.
--
-- Stored as plain JSON. The schema is versioned so future changes can migrate
-- old files instead of asking users to delete them. Errors are surfaced via
-- vim.notify rather than swallowed.

local M = {}

local CURRENT_VERSION = 1
local MAX_RECENT_RUNS = 5

---@class etude.SourceProgress
---@field byte_offset integer  Bytes from start of file the user has consumed.
---@field last_used integer    os.time() when this source was last practiced.

---@class etude.RunRecord
---@field ts integer
---@field source_id string
---@field source_name string
---@field wpm integer
---@field accuracy integer
---@field duration_secs number
---@field chars integer

---@class etude.LifetimeStats
---@field runs integer
---@field wpm_sum integer       Used to derive average WPM.
---@field accuracy_sum integer  Used to derive average accuracy.
---@field total_secs number
---@field total_chars integer

---@class etude.Data
---@field version integer
---@field sources table<string, etude.SourceProgress>
---@field recent etude.RunRecord[]
---@field lifetime etude.LifetimeStats

---@return etude.Data
local function fresh()
  return {
    version = CURRENT_VERSION,
    sources = {},
    recent = {},
    lifetime = { runs = 0, wpm_sum = 0, accuracy_sum = 0, total_secs = 0, total_chars = 0 },
  }
end

---@param raw etude.Data
---@return etude.Data
local function migrate(raw)
  -- Only one version exists today; future versions add branches here.
  if raw.version == CURRENT_VERSION then
    return raw
  end
  -- Unknown future-version data: keep going on a clean slate rather than corrupt.
  vim.notify(
    ("etude: unrecognized data version %s, ignoring saved data"):format(tostring(raw.version)),
    vim.log.levels.WARN
  )
  return fresh()
end

---@param path string
---@return etude.Data
function M.load(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return fresh()
  end

  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    vim.notify("etude: could not open data file: " .. path, vim.log.levels.WARN)
    return fresh()
  end
  local content = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  if not content or content == "" then
    return fresh()
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    vim.notify(
      "etude: could not parse " .. path .. " (data left untouched on disk; using fresh stats this session)",
      vim.log.levels.ERROR
    )
    return fresh()
  end

  -- Defensive: ensure fields exist with the right types.
  local data = migrate(decoded)
  data.sources = data.sources or {}
  data.recent = data.recent or {}
  data.lifetime = data.lifetime
    or { runs = 0, wpm_sum = 0, accuracy_sum = 0, total_secs = 0, total_chars = 0 }
  return data
end

---@param path string
---@param data etude.Data
function M.save(path, data)
  local encoded = vim.json.encode(data)
  -- Atomic-ish write: write to .tmp then rename, so a crash mid-write doesn't truncate.
  local tmp = path .. ".tmp"
  local fd, err = vim.uv.fs_open(tmp, "w", 420) -- 0644
  if not fd then
    vim.notify("etude: could not write data file: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end
  vim.uv.fs_write(fd, encoded, 0)
  vim.uv.fs_close(fd)
  vim.uv.fs_rename(tmp, path)
end

---Update accumulated stats with a finished run.
---@param data etude.Data
---@param run etude.RunRecord
function M.record_run(data, run)
  -- Lifetime is tracked as sums (not running averages) so a single missed
  -- save can't bias future means -- adding the next run is always exact.
  local life = data.lifetime
  life.runs = life.runs + 1
  life.wpm_sum = life.wpm_sum + run.wpm
  life.accuracy_sum = life.accuracy_sum + run.accuracy
  life.total_secs = life.total_secs + run.duration_secs
  life.total_chars = life.total_chars + run.chars

  table.insert(data.recent, 1, run)
  while #data.recent > MAX_RECENT_RUNS do
    table.remove(data.recent)
  end
end

---@param data etude.Data
---@return integer wpm_avg, integer accuracy_avg
function M.averages(data)
  local life = data.lifetime
  if life.runs == 0 then
    return 0, 0
  end
  return math.floor(life.wpm_sum / life.runs), math.floor(life.accuracy_sum / life.runs)
end

---@param data etude.Data
---@param path string  Source file path.
---@return etude.SourceProgress
function M.get_progress(data, path)
  local p = data.sources[path]
  if not p then
    p = { byte_offset = 0, last_used = 0 }
    data.sources[path] = p
  end
  return p
end

return M
