-- Minimal test shim for running tests in nvim headless mode
local M = {}
local failures = {}
local current_describe = ""

function M.describe(name, fn)
  current_describe = name
  fn()
end

function M.it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("  ✓ " .. current_describe .. " > " .. name)
  else
    print("  ✗ " .. current_describe .. " > " .. name)
    print("    " .. tostring(err))
    table.insert(failures, current_describe .. " > " .. name .. ": " .. tostring(err))
  end
end

function M.assert_eq(expected, actual, msg)
  if expected ~= actual then
    error((msg or "") .. " expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual), 2)
  end
end

function M.assert_true(val, msg)
  if not val then
    error((msg or "") .. " expected truthy, got " .. vim.inspect(val), 2)
  end
end

function M.done()
  if #failures > 0 then
    print("\n" .. #failures .. " FAILED")
    vim.cmd("cq 1")
  else
    print("\nAll passed")
    vim.cmd("qa!")
  end
end

return M
