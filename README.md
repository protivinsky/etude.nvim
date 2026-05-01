# etude.nvim

A minimal typing-practice plugin for Neovim. Type along with text files you
choose, and pick up the next session from where you left off.

```
┌──────────────────────────── etude ────────────────────────────┐
│ Sherlock                                       Lines  3 6 9   │
│                                                               │
│ It is a capital mistake to theorize before one has data.      │
│ Insensibly one begins to twist facts to suit theories,        │
│ instead of theories to suit facts.                            │
│                                                               │
│ 12s   72 wpm   96% acc                                        │
│ i start  <Esc> stop  <C-r> restart  <C-n> next  q quit        │
└───────────────────────────────────────────────────────────────┘
```

## Why

Typr and friends are great, but I wanted something smaller, that **practices
on text I actually care about reading anyway**, and **remembers where I
left off** so each session continues the previous one.

## Features

- **Resume by source.** Per-file byte-offset bookmark; the next session
  continues from the next line.
- **Built-in sources.** Curated phrases and random words (with optional
  numbers/symbols), in case you want a quick warm-up.
- **Picker.** `:Etude` opens `vim.ui.select` — any picker plugin that
  overrides the hook (telescope-ui-select, dressing, snacks, mini.pick,
  fzf-lua) works transparently.
- **Live WPM and accuracy** during the run; lifetime averages + last 5
  runs in `:Etude stats`.
- **Follows your colorscheme** — highlights link to standard groups
  (`Comment`, `DiagnosticOk`, `DiagnosticError`, `Title`).
- **Plain-JSON persistence**, schema-versioned, atomic writes.
- **Cleans up your text files** — smart quotes (`“ ” ‘ ’`) become straight ones,
  em/en dashes become `--`/`-`, ellipsis becomes `...`, non-breaking spaces
  become regular ones, line breaks/tabs collapse to spaces, and anything left
  outside printable ASCII is dropped. Set `normalize = false` on a source to
  keep the raw bytes (useful for code).

## Install (lazy.nvim)

```lua
{
  "protivinsky/etude.nvim",
  cmd = { "Etude" },
  opts = {
    sources = {
      { path = "~/notes/practice/sherlock.txt", name = "Sherlock" },
      { path = "~/notes/practice/code.lua",     name = "Lua tricks" },
    },
  },
}
```

## Usage

| Command         | What it does                                                   |
| --------------- | -------------------------------------------------------------- |
| `:Etude`        | Open the source picker.                                        |
| `:Etude resume` | Re-open the most recent source (or picker if no history).      |
| `:Etude stats`  | Lifetime averages + last 5 runs.                               |

In the practice window:

| Key      | Action                                                |
| -------- | ----------------------------------------------------- |
| `i`      | Start typing                                          |
| `<Esc>`  | Leave Insert mode (`<Esc>` again or `q` to close)     |
| `q`      | Close                                                 |
| `<C-r>`  | Restart current chunk                                 |
| `<C-n>`  | Save bookmark, load next chunk (file sources)         |
| `<C-p>`  | Step back to the previous chunk (file sources)        |
| `3/6/9`  | Set rows per chunk (persisted across sessions)        |

## Configuration

Defaults (all keys optional):

```lua
{
  sources = {
    -- Each source: { path = "...", name = "...", normalize = true }
    -- `normalize` defaults to true. Set it to false for code or any file
    -- where exact whitespace and characters matter.
    -- { path = "~/notes/sherlock.txt",        name = "Sherlock" },
    -- { path = "~/snippets/lua-tricks.lua",   name = "Lua tricks", normalize = false },
  },
  width = 84,                        -- float width in columns (default fits the key hints row)
  line_count = 3,                    -- 3 / 6 / 9 rows per chunk
  wpm_goal = 80,
  data_file = vim.fn.stdpath("data") .. "/etude.json",
  random = {
    word_min_len = 2,
    word_max_len = 7,
    number_chance = 0.15,
    symbol_chance = 0.0,
  },
  -- Per-group highlight overrides. String = link, table = full hl spec.
  -- The float surface (NormalFloat / FloatBorder / EndOfBuffer) is taken
  -- from the global Normal automatically, so it always matches your
  -- regular buffers; the keys below cover the foreground colors.
  highlights = {
    -- pending     = "Conceal",                      -- a touch brighter than Comment on most themes
    -- pending     = { fg = "#7f848e" },             -- or pin an exact color
    -- correct     = "DiagnosticOk",
    -- wrong       = "DiagnosticError",
    -- wrong_space = { link = "DiagnosticError" },
    -- header      = "Title",
    -- key         = "Special",
    -- key_active  = "DiagnosticOk",
    -- muted       = "Comment",
    -- accent      = "Statement",
  },
  on_attach = function(buf) end,
}
```

If the pending text feels too dim, the most useful knob is `highlights.pending`
— try `"Conceal"`, `"Whitespace"`, `"LineNr"`, or pin an exact color with
`{ fg = "#7f848e" }`.

## Disabling completion popups

Etude buffers have `filetype = "etude"` and the built-in `'complete'` /
`'omnifunc'` options cleared, but third-party completion plugins don't read
those — disable them in *their* config keyed on the etude filetype:

```lua
-- nvim-cmp
require("cmp").setup({
  enabled = function() return vim.bo.filetype ~= "etude" end,
})

-- blink.cmp
require("blink.cmp").setup({
  enabled = function() return vim.bo.filetype ~= "etude" end,
})
```

For mini.completion (which uses a buffer-local flag) the etude `on_attach`
hook is the right place.

## Credits

- The UX — overlaying expected text via extmarks, the `3 / 6 / 9` line-count
  selector, the in-window mappings, the general feel — is heavily inspired by
  [**Typr**](https://github.com/nvzone/typr) by [nvzone](https://github.com/nvzone).
  etude is a smaller, more opinionated cousin focused on resumable
  user-supplied texts; if you want a richer stats dashboard, an activity
  heatmap, or a per-keyboard-layout heatmap, check out Typr.
- The plugin layout (`lua/<name>/{init,config,health,types}.lua`, `plugin/`,
  `doc/`, `spec/`, the busted setup) follows
  [**base.nvim**](https://github.com/S1M0N38/base.nvim) by
  [S1M0N38](https://github.com/S1M0N38) — a clean, minimal Neovim plugin
  template that I'd recommend as a starting point for similar projects.

## License

MIT. See `LICENSE`.
