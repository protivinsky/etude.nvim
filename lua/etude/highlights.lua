local M = {}

-- Highlight groups defined on a private namespace which is then attached to
-- the etude window via nvim_win_set_hl_ns -- the float gets its own visual
-- treatment without touching global state.
--
-- The float surface (NormalFloat) is forced to match the global Normal
-- background so etude doesn't visually diverge from the user's regular
-- buffers. We can't just `link = "Normal"` from within a non-zero namespace
-- (the link survives but the float renderer doesn't appear to chase it back
-- to the global Normal) -- so we copy the bg explicitly. We also propagate
-- that bg to a handful of related groups (CursorLine, NonText,
-- EndOfBuffer, FloatBorder) so the float's interior is uniform.

---@param group string
---@return integer? bg, integer? fg
local function get_global(group)
  local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
  if not hl or vim.tbl_isempty(hl) then
    return nil, nil
  end
  return hl.bg, hl.fg
end

---@param n integer?
---@return string?
local function hex(n)
  if not n then return nil end
  return string.format("#%06x", n)
end

---@param ns integer
function M.setup(ns)
  local set = vim.api.nvim_set_hl

  -- Float surface -- match Normal bg explicitly.
  local normal_bg, normal_fg = get_global("Normal")
  if normal_bg then
    local bg = hex(normal_bg)
    set(ns, "NormalFloat", { fg = hex(normal_fg), bg = bg })
    set(ns, "EndOfBuffer", { fg = bg, bg = bg })
    set(ns, "CursorLine", { bg = bg })
    set(ns, "NonText", { bg = bg })
    -- Border keeps its own fg from the colorscheme but uses our bg, so the
    -- corner cells don't render with a different shade.
    local _, border_fg = get_global("FloatBorder")
    set(ns, "FloatBorder", { fg = hex(border_fg or normal_fg), bg = bg })
  end

  -- Diff coloring
  set(ns, "EtudePending", { link = "Comment", default = true })
  set(ns, "EtudeCorrect", { link = "DiagnosticOk", default = true })
  set(ns, "EtudeWrong", { link = "DiagnosticError", default = true })
  set(ns, "EtudeWrongSpace", { link = "DiagnosticError", default = true })
  -- Chrome
  set(ns, "EtudeHeader", { link = "Title", default = true })
  set(ns, "EtudeKey", { link = "Special", default = true })
  set(ns, "EtudeKeyActive", { link = "DiagnosticOk", default = true })
  set(ns, "EtudeMuted", { link = "Comment", default = true })
  set(ns, "EtudeAccent", { link = "Statement", default = true })

  -- User overrides from config.highlights. Keys are friendly snake_case names.
  -- A string value is treated as a link target; a table is passed through as
  -- a full highlight spec. Overrides come last so they replace the defaults.
  local KEY_TO_GROUP = {
    pending = "EtudePending",
    correct = "EtudeCorrect",
    wrong = "EtudeWrong",
    wrong_space = "EtudeWrongSpace",
    header = "EtudeHeader",
    key = "EtudeKey",
    key_active = "EtudeKeyActive",
    muted = "EtudeMuted",
    accent = "EtudeAccent",
  }
  local user_hl = require("etude.config").values.highlights or {}
  for key, spec in pairs(user_hl) do
    local group = KEY_TO_GROUP[key]
    if group then
      if type(spec) == "string" then
        set(ns, group, { link = spec })
      elseif type(spec) == "table" then
        set(ns, group, spec)
      end
    end
  end
end

return M
