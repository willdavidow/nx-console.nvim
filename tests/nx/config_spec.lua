local t = require("tests.test_helper")
local config = require("nx.config")

t.describe("config defaults", function()
  config.reset()
  config.setup({})
  local c = config.get()

  t.it("has auto_detect true by default", function()
    t.assert_true(c.workspace.auto_detect)
  end)

  t.it("has cache_ttl 30 by default", function()
    t.assert_eq(30, c.workspace.cache_ttl)
  end)

  t.it("has terminal_style float by default", function()
    t.assert_eq("float", c.runner.terminal_style)
  end)
end)

t.describe("config merging", function()
  config.reset()
  config.setup({ workspace = { cache_ttl = 60 }, runner = { terminal_style = "split" } })
  local c = config.get()

  t.it("preserves untouched defaults", function()
    t.assert_true(c.workspace.auto_detect)
    t.assert_eq(0.7, c.runner.float_height)
  end)

  t.it("applies user overrides", function()
    t.assert_eq(60, c.workspace.cache_ttl)
    t.assert_eq("split", c.runner.terminal_style)
  end)
end)

t.describe("config reset isolation", function()
  config.reset()
  config.setup({ workspace = { cache_ttl = 99 } })
  config.reset()
  config.setup({})

  t.it("does not leak state between reset calls", function()
    t.assert_eq(30, config.get().workspace.cache_ttl)
  end)
end)

t.done()
