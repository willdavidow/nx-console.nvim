local t = require("tests.test_helper")
local utils = require("nx.utils")

t.describe("utils.exec", function()
  t.it("runs a command and returns stdout via callback", function()
    local done = false
    local result = nil
    utils.exec({ "echo", "hello" }, function(out)
      result = out
      done = true
    end)
    vim.wait(2000, function() return done end)
    t.assert_eq("hello\n", result)
  end)

  t.it("calls on_error callback on non-zero exit", function()
    local done = false
    local err_msg = nil
    utils.exec({ "sh", "-c", "exit 1" }, function() end, function(err)
      err_msg = err
      done = true
    end)
    vim.wait(2000, function() return done end)
    t.assert_true(err_msg ~= nil, "expected error callback to fire")
  end)
end)

t.describe("utils.find_up", function()
  t.it("finds a file by walking up directories", function()
    local root = vim.fn.tempname() .. "/nx-test"
    local deep = root .. "/sub/deep"
    vim.fn.mkdir(deep, "p")
    local f = io.open(root .. "/nx.json", "w")
    f:write("{}")
    f:close()

    local found = utils.find_up("nx.json", deep)
    t.assert_eq(root, found)

    vim.fn.delete(root, "rf")
  end)

  t.it("returns nil when file not found", function()
    local found = utils.find_up("nx.json", "/tmp")
    t.assert_eq(nil, found)
  end)
end)

t.done()
