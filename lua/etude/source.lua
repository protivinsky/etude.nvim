-- Text sources: file, phrases, random.
--
-- A source produces a chunk: { lines, advance, eof }, where
--   lines:   N strings to display, each <= width
--   advance: bytes consumed from the source (for files, drives the bookmark)
--   eof:    true if the source is exhausted (file source only).

local M = {}

local words_list = require("etude.words")
local phrases_list = require("etude.phrases")
local config = require("etude.config")
local text_mod = require("etude.text")

---@class etude.Chunk
---@field lines string[]
---@field advance integer    Source bytes "consumed" by this chunk (files only; 0 otherwise).
---@field eof boolean

-- ---------------------------------------------------------------------------
-- Word-wrap a single block of source text into N lines of <= width chars.
-- Returns the lines, the total characters consumed (including separating
-- whitespace and trailing whitespace skipped), and a boolean eof flag.
-- ---------------------------------------------------------------------------
---@param text string
---@param width integer
---@param line_count integer
---@param start integer  1-based byte index into text.
---@return string[] lines, integer consumed_bytes, boolean eof
local function wrap_lines(text, width, line_count, start)
  local lines = {}
  local pos = start
  local n = #text

  -- Skip any leading whitespace at the very start of the chunk.
  while pos <= n and text:sub(pos, pos):match("%s") do
    pos = pos + 1
  end
  local chunk_start = pos

  for _ = 1, line_count do
    if pos > n then
      break
    end
    local line_start = pos
    local last_break = nil  -- last whitespace position seen on this line

    while pos <= n do
      local ch = text:sub(pos, pos)
      if ch == "\n" then
        -- treat newline as a hard break: stop the line here.
        break
      end
      local line_len = pos - line_start + 1
      if ch:match("%s") then
        last_break = pos
      end
      if line_len > width then
        -- Wrap. Prefer the last whitespace; if none, hard-cut at width.
        if last_break and last_break > line_start then
          pos = last_break
        else
          pos = line_start + width - 1
        end
        break
      end
      pos = pos + 1
    end

    local line_end = pos - 1
    if pos <= n and text:sub(pos, pos) == "\n" then
      -- consume the newline as part of advance, but don't include it in the line.
      pos = pos + 1
    elseif pos <= n and text:sub(pos, pos):match("%s") then
      -- consume any whitespace separating lines.
      while pos <= n and text:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
    end

    local line = text:sub(line_start, line_end):gsub("%s+$", "")
    if line == "" then
      break
    end
    table.insert(lines, line)
  end

  local consumed = pos - chunk_start
  -- "Skipped leading whitespace" also counts as consumed, otherwise the bookmark
  -- doesn't advance past it on subsequent runs.
  consumed = consumed + (chunk_start - start)
  return lines, consumed, pos > n
end

-- ---------------------------------------------------------------------------
-- File source
-- ---------------------------------------------------------------------------

-- Cache normalized file content keyed by (path, mtime, normalize-flag) so
-- repeated chunk reads in one session don't re-read or re-normalize. Cache is
-- module-local; if the file changes on disk, mtime invalidates it.
local file_cache = {}

---@param path string
---@param normalize boolean
---@return string?
local function read_file(path, normalize)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  local cached = file_cache[path]
  local mtime = stat.mtime and stat.mtime.sec or 0
  if cached and cached.mtime == mtime and cached.normalize == normalize then
    return cached.text
  end

  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local content = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  if not content then
    return nil
  end
  if normalize then
    content = text_mod.normalize(content)
  end
  file_cache[path] = { mtime = mtime, normalize = normalize, text = content }
  return content
end

---@param path string
---@param byte_offset integer
---@param width integer
---@param line_count integer
---@param normalize? boolean  Default true. When false, file bytes are read raw.
---@return etude.Chunk?
function M.file_chunk(path, byte_offset, width, line_count, normalize)
  if normalize == nil then
    normalize = true
  end
  local text = read_file(path, normalize)
  if not text then
    return nil
  end

  if byte_offset >= #text then
    -- already at end -- wrap to start
    byte_offset = 0
  end

  local lines, advance, eof = wrap_lines(text, width, line_count, byte_offset + 1)
  if #lines == 0 then
    return { lines = {}, advance = 0, eof = true }
  end
  return { lines = lines, advance = advance, eof = eof }
end

-- ---------------------------------------------------------------------------
-- Random + phrases sources
-- ---------------------------------------------------------------------------

local SYMBOLS = {
  "!", '"', "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/",
  ":", ";", "<", "=", ">", "?", "@", "[", "\\", "]", "^", "_", "`", "{", "|", "}", "~",
}

---@param opts {numbers: boolean, symbols: boolean, random: boolean}
---@return string
local function gen_word(opts)
  local rcfg = config.values.random
  local word

  if opts.numbers and math.random() < (rcfg.number_chance or 0.15) then
    word = tostring(math.random(0, 9999))
  elseif opts.random then
    local len = math.random(rcfg.word_min_len or 2, rcfg.word_max_len or 7)
    local buf = {}
    for i = 1, len do
      buf[i] = string.char(math.random(97, 122))
    end
    word = table.concat(buf)
  else
    word = words_list[math.random(1, #words_list)]
  end

  if opts.symbols and math.random() < (rcfg.symbol_chance or 0.0) then
    word = word .. SYMBOLS[math.random(1, #SYMBOLS)]
  end
  return word
end

---@param opts {numbers: boolean, symbols: boolean, random: boolean}
---@param width integer
---@param line_count integer
---@return etude.Chunk
function M.random_chunk(opts, width, line_count)
  local lines = {}
  for _ = 1, line_count do
    local words = {}
    local len = 0
    while true do
      local w = gen_word(opts)
      local need = len + #w + (len == 0 and 0 or 1)
      if need > width then
        break
      end
      table.insert(words, w)
      len = need
    end
    if #words == 0 then
      -- Width is too narrow for a single word; force one anyway.
      table.insert(words, gen_word(opts):sub(1, width))
    end
    table.insert(lines, table.concat(words, " "))
  end
  return { lines = lines, advance = 0, eof = false }
end

---@param width integer
---@param line_count integer
---@return etude.Chunk
function M.phrases_chunk(width, line_count)
  -- Concatenate a handful of phrases into one buffer, then word-wrap.
  local buf = {}
  for _ = 1, line_count do
    table.insert(buf, phrases_list[math.random(1, #phrases_list)])
  end
  local text = table.concat(buf, " ")
  local lines, _, _ = wrap_lines(text, width, line_count, 1)
  return { lines = lines, advance = 0, eof = false }
end

-- ---------------------------------------------------------------------------
-- Resolve a Source descriptor into a chunk.
-- ---------------------------------------------------------------------------

---@class etude.Source
---@field kind "file" | "random" | "phrases"
---@field path? string             For "file" sources.
---@field name string              Display label.
---@field id string                Stable id (used in stats).
---@field normalize? boolean       For "file" sources; default true.
---@field random_opts? {numbers: boolean, symbols: boolean, random: boolean}

---@param src etude.Source
---@param byte_offset integer
---@param width integer
---@param line_count integer
---@return etude.Chunk?
function M.chunk(src, byte_offset, width, line_count)
  local chunk
  if src.kind == "file" then
    chunk = M.file_chunk(src.path, byte_offset, width, line_count, src.normalize)
  elseif src.kind == "random" then
    chunk = M.random_chunk(src.random_opts or { numbers = false, symbols = false, random = false }, width, line_count)
  elseif src.kind == "phrases" then
    chunk = M.phrases_chunk(width, line_count)
  end
  if not chunk or #chunk.lines == 0 then
    return chunk
  end

  -- Append a trailing space to every line except the last so that typing
  -- reads as continuous prose: at a soft line wrap the user types a normal
  -- word-boundary space, which advances the cursor to the next row. Without
  -- this, two consecutive words split across a wrap visually merge as one.
  for i = 1, #chunk.lines - 1 do
    chunk.lines[i] = chunk.lines[i] .. " "
  end
  return chunk
end

-- ---------------------------------------------------------------------------
-- Picker source list
-- ---------------------------------------------------------------------------

---@return etude.Source[]
function M.list_all()
  local out = {}
  for _, file in ipairs(config.values.sources or {}) do
    table.insert(out, {
      kind = "file",
      path = file.path,
      name = file.name,
      id = "file:" .. file.path,
      normalize = file.normalize,
    })
  end
  table.insert(out, {
    kind = "phrases",
    name = "Phrases (built-in prose)",
    id = "builtin:phrases",
  })
  table.insert(out, {
    kind = "random",
    name = "Common words",
    id = "builtin:random_common",
    random_opts = { numbers = false, symbols = false, random = false },
  })
  table.insert(out, {
    kind = "random",
    name = "Random letters + numbers + symbols",
    id = "builtin:random_full",
    random_opts = { numbers = true, symbols = true, random = true },
  })
  return out
end

return M
