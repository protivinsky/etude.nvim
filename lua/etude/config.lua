---@class etude.Config
local M = {}

---@class etude.UserConfig
---@field sources? etude.SourceSpec[]    User-supplied practice files.
---@field width? integer                  Float window width (default 80).
---@field line_count? integer             Default rows per chunk (3, 6, or 9).
---@field wpm_goal? integer               Goal for the progress bar.
---@field data_file? string               Path to persisted JSON data.
---@field random? etude.RandomConfig      Random-mode generator settings.
---@field highlights? table<string, string|vim.api.keyset.highlight>
---       Override etude's highlight groups. Keys: pending / correct / wrong /
---       wrong_space / header / key / key_active / muted / accent. Each value
---       is either a string (linked group name) or a full highlight spec
---       table -- e.g. { fg = "#abb2bf", bold = true }.
---@field on_attach? fun(buf: integer)    Callback when a practice buffer opens.

---@class etude.SourceSpec
---@field path string                     Absolute or ~-expanded file path.
---@field name? string                    Display name (default: basename).
---@field normalize? boolean              Default true. When false, the file's
---                                       raw bytes are used. Set this to false
---                                       for code files where exact whitespace
---                                       and characters matter.

---@class etude.RandomConfig
---@field word_min_len? integer           Min length for purely random words.
---@field word_max_len? integer           Max length for purely random words.
---@field number_chance? number           Probability (0–1) a token is a number.
---@field symbol_chance? number           Probability (0–1) a token gets a trailing symbol.

---@type etude.UserConfig
M.defaults = {
  sources = {},
  -- 84 fits the full footer key hint row (~78 chars) with PAD margins on
  -- both sides. Drop to 80 only if you don't mind "quit" hugging the border.
  width = 84,
  line_count = 3,
  wpm_goal = 80,
  data_file = vim.fn.stdpath("data") .. "/etude.json",
  random = {
    word_min_len = 2,
    word_max_len = 7,
    number_chance = 0.15,
    symbol_chance = 0.0,
  },
  highlights = {},
  on_attach = nil,
}

---@type etude.UserConfig
M.values = vim.deepcopy(M.defaults)

---@param opts etude.UserConfig?
function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})

  -- Normalize source paths once, so we never re-expand at runtime.
  for _, src in ipairs(M.values.sources or {}) do
    src.path = vim.fn.fnamemodify(src.path, ":p")
    src.name = src.name or vim.fn.fnamemodify(src.path, ":t")
  end
end

return M
