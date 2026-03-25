local M = {}

local function has_snacks()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks or nil
end

--- @param msg string
--- @param level? number vim.log.levels (default INFO)
function M.info(msg, level)
  local snacks = has_snacks()
  if snacks and snacks.notifier then
    snacks.notifier.notify(msg, {
      level = level or vim.log.levels.INFO,
      title = "Nx",
    })
  else
    vim.notify("[Nx] " .. msg, level or vim.log.levels.INFO)
  end
end

function M.warn(msg)
  M.info(msg, vim.log.levels.WARN)
end

function M.error(msg)
  M.info(msg, vim.log.levels.ERROR)
end

return M
