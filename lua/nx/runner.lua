local workspace = require("nx.workspace")
local config = require("nx.config")
local notify = require("nx.notify")
local history = require("nx.history")

local M = {}

local running_tasks = {}

--- Check if a target name is typically long-running.
--- @param target string
--- @return boolean
function M.is_long_running(target)
  local names = config.get().runner.long_running_targets or {}
  for _, name in ipairs(names) do
    if target == name then
      return true
    end
  end
  return false
end

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

  -- Long-running targets always use a split, never a float
  local effective_style = cfg.terminal_style
  if M.is_long_running(target) and effective_style == "float" then
    effective_style = "split"
  end

  if effective_style == "float" then
    opts.win = {
      style = "terminal",
      position = "float",
      width = cfg.float_width,
      height = cfg.float_height,
      title = " " .. icons.nx .. " " .. cmd .. " ",
      border = "rounded",
    }
  elseif effective_style == "split" then
    opts.win = {
      style = "terminal",
      position = "bottom",
    }
  elseif effective_style == "vsplit" then
    opts.win = {
      style = "terminal",
      position = "right",
    }
  end

  local start_time = vim.uv.now()
  notify.info(icons.running .. " Running " .. label)

  local term = snacks.terminal(cmd, opts)

  local task_entry = {
    project = project,
    target = target,
    cmd = cmd,
    start_time = start_time,
    term = term,
  }
  table.insert(running_tasks, task_entry)

  -- Wire up completion notification via TermClose event
  if cfg.notify_on_complete and term and term.buf then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = term.buf,
      once = true,
      callback = function()
        -- Remove from running tasks
        for i, t in ipairs(running_tasks) do
          if t == task_entry then
            table.remove(running_tasks, i)
            break
          end
        end

        local elapsed = (vim.uv.now() - start_time) / 1000
        local duration = string.format("%.1fs", elapsed)
        local exit_code = vim.v.event and vim.v.event.status or -1
        if exit_code == 0 then
          notify.info(icons.success .. " " .. label .. " completed in " .. duration)
        else
          notify.error(icons.failure .. " " .. label .. " failed (exit " .. exit_code .. ") in " .. duration)
        end

        local hist_entry = {
          project = project,
          target = target,
          cmd = cmd,
          args = extra_args,
          exit_code = exit_code,
          duration = elapsed,
          _term_buf = term and term.buf or nil,
        }
        history.add(hist_entry)
        history.save()
      end,
    })
  end
end

--- Get the number of currently running tasks.
--- @return number
function M.running_count()
  return #running_tasks
end

--- Stop all running tasks (or filtered by project/target).
--- @param project? string filter by project name
--- @param target? string filter by target name
function M.stop(project, target)
  local to_stop = {}
  for i = #running_tasks, 1, -1 do
    local t = running_tasks[i]
    local match = true
    if project and t.project ~= project then match = false end
    if target and t.target ~= target then match = false end
    if match then
      table.insert(to_stop, t)
    end
  end

  if #to_stop == 0 then
    notify.warn("No running tasks to stop")
    return
  end

  for _, t in ipairs(to_stop) do
    if t.term and t.term.buf and vim.api.nvim_buf_is_valid(t.term.buf) then
      local chan = vim.bo[t.term.buf].channel
      if chan and chan > 0 then
        vim.fn.jobstop(chan)
      end
    end
  end
  notify.info("Stopped " .. #to_stop .. " task(s)")
end

--- Re-run the most recent command from history.
function M.rerun()
  local ok, history = pcall(require, "nx.history")
  if not ok then
    notify.warn("No history module available")
    return
  end
  local entries = history.list()
  if #entries == 0 then
    notify.warn("No previous runs to repeat")
    return
  end
  local last = entries[1]
  M.run(last.project, last.target, last.args)
end

return M
