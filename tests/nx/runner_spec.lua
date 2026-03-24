local t = require("tests.test_helper")
local runner = require("nx.runner")

t.describe("runner.is_long_running", function()
  t.it("returns true for serve targets", function()
    t.assert_true(runner.is_long_running("serve"))
  end)

  t.it("returns true for dev targets", function()
    t.assert_true(runner.is_long_running("dev"))
  end)

  t.it("returns true for start targets", function()
    t.assert_true(runner.is_long_running("start"))
  end)

  t.it("returns true for watch targets", function()
    t.assert_true(runner.is_long_running("watch"))
  end)

  t.it("returns false for build targets", function()
    t.assert_eq(false, runner.is_long_running("build"))
  end)

  t.it("returns false for test targets", function()
    t.assert_eq(false, runner.is_long_running("test"))
  end)

  t.it("returns false for lint targets", function()
    t.assert_eq(false, runner.is_long_running("lint"))
  end)
end)

t.done()
