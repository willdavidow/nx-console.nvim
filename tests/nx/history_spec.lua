local t = require("tests.test_helper")

local test_path = vim.fn.tempname() .. "/nx-test-history.json"
local history = require("nx.history")
history._set_path(test_path)

t.describe("history.add", function()
  t.it("adds an entry to history", function()
    history.reset()
    history.add({
      project = "my-app",
      target = "build",
      cmd = "npx nx run my-app:build",
      exit_code = 0,
      duration = 12.4,
    })
    local entries = history.list()
    t.assert_eq(1, #entries)
    t.assert_eq("my-app", entries[1].project)
    t.assert_eq("build", entries[1].target)
    t.assert_eq(0, entries[1].exit_code)
  end)
end)

t.describe("history.persist and load", function()
  t.it("persists to disk and reloads", function()
    history.reset()
    history.add({
      project = "my-app",
      target = "build",
      cmd = "npx nx run my-app:build",
      exit_code = 0,
      duration = 12.4,
    })
    history.save()
    history.reset()
    history.load()
    local entries = history.list()
    t.assert_eq(1, #entries)
    t.assert_eq("my-app", entries[1].project)
  end)
end)

t.describe("history.remove", function()
  t.it("removes an entry by index", function()
    history.reset()
    history.add({ project = "a", target = "build", cmd = "a", exit_code = 0, duration = 1 })
    history.add({ project = "b", target = "test", cmd = "b", exit_code = 1, duration = 2 })
    history.remove(1)
    local entries = history.list()
    t.assert_eq(1, #entries)
    t.assert_eq("a", entries[1].project)
  end)
end)

t.describe("history.format_relative_time", function()
  t.it("formats seconds ago", function()
    local now = os.time()
    local result = history.format_relative_time(now - 30)
    t.assert_eq("30s ago", result)
  end)

  t.it("formats minutes ago", function()
    local now = os.time()
    local result = history.format_relative_time(now - 120)
    t.assert_eq("2 min ago", result)
  end)

  t.it("formats hours ago", function()
    local now = os.time()
    local result = history.format_relative_time(now - 3600)
    t.assert_eq("1 hr ago", result)
  end)
end)

t.describe("history max_entries", function()
  t.it("trims oldest entries when exceeding max", function()
    history.reset()
    for i = 1, 105 do
      history.add({ project = "p" .. i, target = "build", cmd = "c", exit_code = 0, duration = 1 })
    end
    local entries = history.list()
    t.assert_eq(100, #entries)
    t.assert_eq("p105", entries[1].project)
    t.assert_eq("p6", entries[100].project)
  end)
end)

vim.fn.delete(vim.fn.fnamemodify(test_path, ":h"), "rf")

t.done()
