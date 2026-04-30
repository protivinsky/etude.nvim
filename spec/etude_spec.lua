-- Pure-Lua unit tests for etude.nvim. Designed to run under busted with
-- `nlua` (Neovim's Lua runtime), so `vim.*` is available.
--
--   busted spec/etude_spec.lua

local function reload(mod)
  package.loaded[mod] = nil
  return require(mod)
end

describe("etude.config", function()
  local config = reload("etude.config")

  it("merges user config over defaults", function()
    config.setup({ width = 100, sources = { { path = "/tmp/x" } } })
    assert.are.equal(100, config.values.width)
    assert.are.equal(3, config.values.line_count) -- default preserved
    assert.are.equal("/tmp/x", config.values.sources[1].path)
    assert.are.equal("x", config.values.sources[1].name) -- default name = basename
  end)

  it("does not mutate defaults", function()
    config.setup({ width = 999 })
    assert.are.equal(80, config.defaults.width)
  end)
end)

describe("etude.data", function()
  local data_mod = reload("etude.data")
  local tmp = vim.fn.tempname() .. ".etude.json"

  it("returns a fresh struct when the file is missing", function()
    os.remove(tmp)
    local data = data_mod.load(tmp)
    assert.are.equal(1, data.version)
    assert.are.equal(0, data.lifetime.runs)
    assert.are.equal(0, #data.recent)
  end)

  it("round-trips a saved run", function()
    os.remove(tmp)
    local data = data_mod.load(tmp)
    data_mod.record_run(data, {
      ts = 1000, source_id = "x", source_name = "x",
      wpm = 60, accuracy = 95, duration_secs = 30, chars = 150,
    })
    data_mod.save(tmp, data)

    local reloaded = data_mod.load(tmp)
    assert.are.equal(1, reloaded.lifetime.runs)
    assert.are.equal(60, reloaded.lifetime.wpm_sum)
    assert.are.equal(1, #reloaded.recent)
    assert.are.equal(60, reloaded.recent[1].wpm)
    os.remove(tmp)
  end)

  it("keeps only the last 5 runs", function()
    os.remove(tmp)
    local data = data_mod.load(tmp)
    for i = 1, 8 do
      data_mod.record_run(data, {
        ts = i, source_id = "x", source_name = "x",
        wpm = i * 10, accuracy = 100, duration_secs = 1, chars = 5,
      })
    end
    assert.are.equal(5, #data.recent)
    -- Most recent first
    assert.are.equal(80, data.recent[1].wpm)
    assert.are.equal(40, data.recent[5].wpm)
  end)

  it("computes lifetime averages", function()
    local data = data_mod.load(tmp)
    -- 8 runs of 10..80 wpm => sum=360, avg=45
    local wpm, _ = data_mod.averages(data)
    assert.are.equal(45, wpm)
  end)

  it("survives a corrupt file without crashing", function()
    local f = io.open(tmp, "w")
    f:write("not json {{{")
    f:close()
    local data = data_mod.load(tmp)
    assert.are.equal(0, data.lifetime.runs)
    os.remove(tmp)
  end)
end)

describe("etude.source", function()
  local source = reload("etude.source")

  it("wraps a file's text into bounded lines", function()
    local path = vim.fn.tempname()
    local body = "The quick brown fox jumps over the lazy dog. " ..
      "Sphinx of black quartz, judge my vow. " ..
      "Pack my box with five dozen liquor jugs."
    local f = io.open(path, "w"); f:write(body); f:close()

    local chunk = source.file_chunk(path, 0, 30, 3)
    assert.is_not_nil(chunk)
    assert.are.equal(3, #chunk.lines)
    for _, l in ipairs(chunk.lines) do
      assert.is_true(#l <= 30, "line too long: " .. l)
    end
    assert.is_true(chunk.advance > 0)
    os.remove(path)
  end)

  it("advances offset so a follow-up chunk yields different text", function()
    local path = vim.fn.tempname()
    local body = string.rep("alpha bravo charlie delta echo foxtrot ", 20)
    local f = io.open(path, "w"); f:write(body); f:close()

    local first = source.file_chunk(path, 0, 30, 3)
    local second = source.file_chunk(path, first.advance, 30, 3)
    assert.are_not.equal(first.lines[1], second.lines[1])
    os.remove(path)
  end)

  it("generates random chunks of the requested shape", function()
    local require_config = reload("etude.config")
    require_config.setup({})
    local chunk = source.random_chunk({ numbers = false, symbols = false, random = false }, 30, 3)
    assert.are.equal(3, #chunk.lines)
    for _, l in ipairs(chunk.lines) do
      assert.is_true(#l <= 30)
    end
  end)
end)

describe("etude (public API)", function()
  it("loads without error", function()
    assert.has_no_errors(function()
      reload("etude")
    end)
  end)

  it("setup is a no-op on empty opts", function()
    assert.has_no_errors(function()
      reload("etude").setup({})
    end)
  end)
end)
