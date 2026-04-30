local M = {}

local config = require("etude.config")

function M.check()
  vim.health.start("etude.nvim")

  if vim.fn.has("nvim-0.10") ~= 1 then
    vim.health.error("Neovim ≥ 0.10 is required")
  else
    vim.health.ok("Neovim ≥ 0.10")
  end

  local cfg = config.values
  vim.health.info("data file: " .. cfg.data_file)

  if not cfg.sources or #cfg.sources == 0 then
    vim.health.info("no user sources configured (built-in phrases / random still work)")
  else
    for _, src in ipairs(cfg.sources) do
      if vim.uv.fs_stat(src.path) then
        vim.health.ok(("source ok: %s"):format(src.path))
      else
        vim.health.warn(("source missing: %s"):format(src.path))
      end
    end
  end
end

return M
