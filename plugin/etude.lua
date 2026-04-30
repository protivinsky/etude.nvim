if vim.g.loaded_etude then
  return
end
vim.g.loaded_etude = true

-- :Etude with optional subcommand
--   :Etude            -> open picker (default)
--   :Etude pick       -> open picker
--   :Etude resume     -> resume last source
--   :Etude stats      -> show stats
local subcommands = {
  pick = function() require("etude").pick() end,
  resume = function() require("etude").resume() end,
  stats = function() require("etude").stats() end,
}

vim.api.nvim_create_user_command("Etude", function(opts)
  local sub = opts.args
  if sub == "" or sub == nil then
    require("etude").pick()
    return
  end
  local fn = subcommands[sub]
  if not fn then
    vim.notify("etude: unknown subcommand: " .. sub, vim.log.levels.ERROR)
    return
  end
  fn()
end, {
  nargs = "?",
  desc = "etude: typing practice",
  complete = function(arglead)
    local out = {}
    for k in pairs(subcommands) do
      if k:find(arglead, 1, true) == 1 then
        table.insert(out, k)
      end
    end
    return out
  end,
})
