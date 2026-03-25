local t = require("tests.test_helper")
local workspace = require("nx.workspace")

t.describe("workspace.detect", function()
  t.it("finds workspace root from a nested directory", function()
    local root = vim.fn.tempname() .. "/ws-test"
    local nested = root .. "/apps/my-app/src"
    vim.fn.mkdir(nested, "p")
    local f = io.open(root .. "/nx.json", "w")
    f:write('{}')
    f:close()

    workspace.reset()
    local found = workspace.detect(nested)
    t.assert_eq(root, found)

    vim.fn.delete(root, "rf")
  end)

  t.it("returns nil when no nx.json exists", function()
    workspace.reset()
    local found = workspace.detect("/tmp")
    t.assert_eq(nil, found)
  end)

  t.it("caches the workspace root after first detection", function()
    local root = vim.fn.tempname() .. "/ws-cache"
    vim.fn.mkdir(root, "p")
    local f = io.open(root .. "/nx.json", "w")
    f:write('{}')
    f:close()

    workspace.reset()
    local first = workspace.detect(root)
    -- Remove nx.json — should still return cached value
    os.remove(root .. "/nx.json")
    local second = workspace.detect(root .. "/sub")
    t.assert_eq(first, second)

    vim.fn.delete(root, "rf")
  end)
end)

t.describe("workspace.nx_bin", function()
  t.it("returns npx nx when no local binary found", function()
    workspace.reset()
    local root = vim.fn.tempname() .. "/ws-bin"
    vim.fn.mkdir(root, "p")
    local f = io.open(root .. "/nx.json", "w")
    f:write('{}')
    f:close()
    workspace.detect(root)

    local bin = workspace.nx_bin()
    t.assert_eq("npx nx", bin)

    vim.fn.delete(root, "rf")
  end)
end)

t.done()
