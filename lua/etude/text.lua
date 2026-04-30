-- Text normalization for the file source.
--
-- Practice files come in many shapes: pasted prose with smart quotes,
-- ebooks with non-breaking spaces, code with tabs. This module turns
-- whatever's on disk into a single stream of printable ASCII separated
-- by single spaces -- which is what you can actually type at a
-- US-keyboard practice session.

local M = {}

-- Multi-byte UTF-8 sequences we replace with ASCII equivalents.
-- Each key is the literal byte sequence; using gsub on bytes is faster
-- and avoids depending on iconv / a UTF-8 library.
local UTF8_REPLACEMENTS = {
  -- Smart quotes
  ["\226\128\156"] = '"',   -- U+201C left double quotation mark
  ["\226\128\157"] = '"',   -- U+201D right double quotation mark
  ["\226\128\152"] = "'",   -- U+2018 left single quotation mark
  ["\226\128\153"] = "'",   -- U+2019 right single quotation mark
  -- Dashes
  ["\226\128\148"] = "--",  -- U+2014 em dash
  ["\226\128\147"] = "-",   -- U+2013 en dash
  -- Misc
  ["\226\128\166"] = "...", -- U+2026 ellipsis
  ["\194\160"] = " ",       -- U+00A0 non-breaking space
}

---Normalize text for typing practice.
---
---  - CRLF / CR -> LF
---  - newlines and tabs -> single space (paragraph layout is dropped on
---    purpose; chunking word-wraps the resulting flow)
---  - common typographic UTF-8 chars -> ASCII equivalents (see above)
---  - everything else outside printable ASCII (32..126) is dropped
---  - runs of whitespace collapsed; leading/trailing trimmed
---
---@param s string?
---@return string
function M.normalize(s)
  if not s or s == "" then
    return ""
  end

  -- Line endings -> LF, then squash newlines/tabs to spaces. We deliberately
  -- collapse paragraph breaks: a typing chunk that ends after a 5-word
  -- paragraph would be a worse UX than continuous prose.
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  s = s:gsub("\n+", " "):gsub("\t", " ")

  -- Replace common UTF-8 typographic characters with ASCII equivalents.
  for from, to in pairs(UTF8_REPLACEMENTS) do
    s = s:gsub(from, to)
  end

  -- Drop everything outside printable ASCII (space..tilde).
  s = s:gsub("[^\32-\126]", "")

  -- Collapse repeated whitespace and trim the ends.
  s = s:gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

  return s
end

return M
