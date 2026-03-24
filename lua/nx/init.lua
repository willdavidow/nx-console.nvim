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

  vim.api.nvim_create_user_command("NxExplorer", function()
    require("nx.sidebar").toggle()
  end, { desc = "Nx: toggle sidebar explorer" })

  vim.api.nvim_create_user_command("NxHistory", function()
    require("nx.history").picker()
  end, { desc = "Nx: run history picker" })

  vim.api.nvim_create_user_command("NxAffected", function()
    require("nx.pickers").affected()
  end, { desc = "Nx: affected projects picker" })

  vim.api.nvim_create_user_command("NxCurrentProject", function()
    require("nx.pickers").current_file()
  end, { desc = "Nx: current file's project targets" })

  vim.api.nvim_create_user_command("NxRerun", function()
    require("nx.runner").rerun()
  end, { desc = "Nx: re-run last command" })

  vim.api.nvim_create_user_command("NxStop", function()
    require("nx.runner").stop()
  end, { desc = "Nx: stop running task(s)" })

  vim.api.nvim_create_user_command("NxPanel", function()
    require("nx.panel").toggle()
  end, { desc = "Nx: toggle task panel" })

  vim.api.nvim_create_user_command("NxPanelPick", function()
    require("nx.panel").pick()
  end, { desc = "Nx: pick task in panel" })

  vim.api.nvim_create_user_command("NxGenerate", function()
    require("nx.generators").pick()
  end, { desc = "Nx: generator picker + form" })

  vim.api.nvim_create_user_command("NxGraph", function()
    local root = workspace.root()
    if not root then
      require("nx.notify").warn("No Nx workspace detected")
      return
    end
    local cmd = workspace.nx_bin() .. " graph"
    require("nx.notify").info("Opening Nx graph in browser...")
    vim.fn.jobstart(cmd, { cwd = root, detach = true })
  end, { desc = "Nx: open project graph in browser" })

  -- Register keymaps
  local keys = cfg.keys
  if keys.projects then
    vim.keymap.set("n", keys.projects, "<cmd>NxProjects<cr>", { desc = "Nx: projects" })
  end
  if keys.refresh then
    vim.keymap.set("n", keys.refresh, "<cmd>NxRefresh<cr>", { desc = "Nx: refresh" })
  end
  if keys.explorer then
    vim.keymap.set("n", keys.explorer, "<cmd>NxExplorer<cr>", { desc = "Nx: explorer" })
  end
  if keys.history then
    vim.keymap.set("n", keys.history, "<cmd>NxHistory<cr>", { desc = "Nx: history" })
  end
  if keys.affected then
    vim.keymap.set("n", keys.affected, "<cmd>NxAffected<cr>", { desc = "Nx: affected" })
  end
  if keys.current then
    vim.keymap.set("n", keys.current, "<cmd>NxCurrentProject<cr>", { desc = "Nx: current project" })
  end
  if keys.rerun then
    vim.keymap.set("n", keys.rerun, "<cmd>NxRerun<cr>", { desc = "Nx: rerun last" })
  end
  if keys.stop then
    vim.keymap.set("n", keys.stop, "<cmd>NxStop<cr>", { desc = "Nx: stop tasks" })
  end
  if keys.generate then
    vim.keymap.set("n", keys.generate, "<cmd>NxGenerate<cr>", { desc = "Nx: generate" })
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

  -- Load run history
  require("nx.history").load()

  -- Register dashboard section if Snacks.dashboard is available
  require("nx.dashboard").register()

  -- Save history on exit as a safety net
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("NxHistorySave", { clear = true }),
    callback = function()
      require("nx.history").save()
    end,
  })
end

--- Return the workspace root, or nil.
--- @return string|nil
function M.workspace_root()
  return workspace.root()
end

--- Detect which project the current buffer belongs to.
--- @param callback? fun(name: string|nil) if provided, fetches async
--- @return string|nil project name (only if cache is warm and no callback)
function M.current_project(callback)
  local ws_root = workspace.root()
  if not ws_root then
    if callback then callback(nil) end
    return nil
  end

  local buf_path = vim.fn.expand("%:p")
  if buf_path == "" then
    if callback then callback(nil) end
    return nil
  end

  local projects_mod = require("nx.projects")

  local function find_match(root_map)
    local best_match = nil
    local best_len = 0
    for name, info in pairs(root_map) do
      local project_path = ws_root .. "/" .. info.root
      if buf_path:sub(1, #project_path) == project_path and #project_path > best_len then
        best_match = name
        best_len = #project_path
      end
    end
    return best_match
  end

  if callback then
    projects_mod.root_map(function(map)
      callback(find_match(map))
    end)
  else
    local detail_cache = projects_mod._get_cache()
    if not detail_cache or not next(detail_cache) then return nil end
    local map = {}
    for name, detail in pairs(detail_cache) do
      map[name] = { root = detail.root, type = detail.type }
    end
    return find_match(map)
  end
end

--- Get the count of currently running tasks.
--- @return number
function M.running_tasks()
  return require("nx.runner").running_count()
end

return M
