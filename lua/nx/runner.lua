local workspace = require("nx.workspace")
local config = require("nx.config")
local notify = require("nx.notify")

local M = {}

--- Run an nx target.
--- @param project string project name
--- @param target string target name
--- @param extra_args? string additional CLI flags
function M.run(project, target, extra_args)
  local root = workspace.root()
  if not root then
    notify.warn("No Nx workspace detected")
    return
  end

  local cfg = config.get().runner
  local cmd = workspace.nx_bin() .. " run " .. project .. ":" .. target
  if extra_args and extra_args ~= "" then
    cmd = cmd .. " " .. extra_args
  end

  local ok, snacks = pcall(require, "snacks")
  if not ok then
    notify.error("snacks.nvim is required for the task runner")
    return
  end

  local icons = config.get().icons
  local label = project .. ":" .. target

  local opts = {
    cwd = root,
    interactive = false,
    auto_close = false,
  }

  if cfg.terminal_style == "float" then
    opts.win = {
      style = "terminal",
      position = "float",
      width = cfg.float_width,
      height = cfg.float_height,
      title = " " .. icons.nx .. " " .. cmd .. " ",
      border = "rounded",
    }
  elseif cfg.terminal_style == "split" then
    opts.win = {
      style = "terminal",
      position = "bottom",
    }
  elseif cfg.terminal_style == "vsplit" then
    opts.win = {
      style = "terminal",
      position = "right",
    }
  end

  local start_time = vim.uv.now()
  notify.info(icons.running .. " Running " .. label)

  local term = snacks.terminal(cmd, opts)

  -- Wire up completion notification via TermClose event
  if cfg.notify_on_complete and term and term.buf then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = term.buf,
      once = true,
      callback = function()
        local elapsed = (vim.uv.now() - start_time) / 1000
        local duration = string.format("%.1fs", elapsed)
        local exit_code = vim.v.event and vim.v.event.status or -1
        if exit_code == 0 then
          notify.info(icons.success .. " " .. label .. " completed in " .. duration)
        else
          notify.error(icons.failure .. " " .. label .. " failed (exit " .. exit_code .. ") in " .. duration)
        end
      end,
    })
  end
end

return M
