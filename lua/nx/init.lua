local config = require("nx.config")
local workspace = require("nx.workspace")

local M = {}

function M.setup(opts)
  config.setup(opts)

  local cfg = config.get()

  -- Register user commands
  vim.api.nvim_create_user_command("NxProjects", function()
    require("nx.pickers").projects()
  end, { desc = "Nx: project + target picker" })

  vim.api.nvim_create_user_command("NxRefresh", function()
    require("nx.projects").reset()
    workspace.reset()
    workspace.detect()
    require("nx.notify").info("Workspace cache refreshed")
  end, { desc = "Nx: refresh workspace cache" })

  -- Register keymaps
  local keys = cfg.keys
  if keys.projects then
    vim.keymap.set("n", keys.projects, "<cmd>NxProjects<cr>", { desc = "Nx: projects" })
  end
  if keys.refresh then
    vim.keymap.set("n", keys.refresh, "<cmd>NxRefresh<cr>", { desc = "Nx: refresh" })
  end

  -- which-key integration
  local wk_ok, wk = pcall(require, "which-key")
  if wk_ok then
    wk.add({ { "<leader>n", group = "Nx" } })
  end

  -- Auto-detect workspace on setup
  if cfg.workspace.auto_detect then
    workspace.detect()
  end
end

--- Return the workspace root, or nil.
--- @return string|nil
function M.workspace_root()
  return workspace.root()
end

return M
