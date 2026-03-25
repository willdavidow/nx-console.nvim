local t = require("tests.test_helper")
local dashboard = require("nx.dashboard")

t.describe("dashboard.format_items", function()
  t.it("formats history entries as dashboard items", function()
    local entries = {
      { project = "my-app", target = "build", exit_code = 0, duration = 12.4, timestamp = os.time() - 120 },
      { project = "ui-lib", target = "test", exit_code = 1, duration = 3.2, timestamp = os.time() - 3600 },
    }
    local items = dashboard.format_items(entries, 5)
    t.assert_eq(2, #items)
    t.assert_true(items[1].label:find("my%-app:build") ~= nil)
    t.assert_true(items[2].label:find("ui%-lib:test") ~= nil)
  end)

  t.it("respects the limit parameter", function()
    local entries = {}
    for i = 1, 10 do
      table.insert(entries, { project = "p" .. i, target = "build", exit_code = 0, duration = 1, timestamp = os.time() })
    end
    local items = dashboard.format_items(entries, 3)
    t.assert_eq(3, #items)
  end)

  t.it("returns empty table when no entries", function()
    local items = dashboard.format_items({}, 5)
    t.assert_eq(0, #items)
  end)
end)

t.done()
