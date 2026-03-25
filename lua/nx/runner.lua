local workspace = require("nx.workspace")
local config = require("nx.config")
local notify = require("nx.notify")
local history = require("nx.history")

local M = {}

local running_tasks = {}
local user_killed = {} -- bufnr set: suppresses failure notification for user-initiated kills

--- Notify sidebar and other listeners that task state changed.
local function fire_task_changed()
  vim.api.nvim_exec_autocmds("User", { pattern = "NxTaskChanged" })
end

--- Check if a target name is typically long-running.
--- Matches if the target equals or contains any pattern in the configured list.
--- @param target string
--- @return boolean
function M.is_long_running(target)
  local patterns = config.get().runner.long_running_targets or {}
  for _, pattern in ipairs(patterns) do
    if target == pattern or target:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

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

  local icons = config.get().icons
  local label = project .. ":" .. target
  local start_time = vim.uv.now()

  notify.info(icons.running .. " Running " .. label)

  -- Long-running tasks go to the persistent panel
  if M.is_long_running(target) then
    local panel = require("nx.panel")

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_call(bufnr, function()
      vim.fn.termopen(cmd, {
        cwd = root,
        on_exit = function(_, exit_code)
          vim.schedule(function()
            -- Keep buffer in panel for output review; user can close manually.
            -- Only remove from the running tasks tracker.
            for i, t in ipairs(running_tasks) do
              if t.buf == bufnr then
                table.remove(running_tasks, i)
                break
              end
            end

            local elapsed = (vim.uv.now() - start_time) / 1000
            local duration = string.format("%.1fs", elapsed)
            local was_killed = user_killed[bufnr]
            user_killed[bufnr] = nil

            if was_killed then
              -- User killed via <C-c> in panel — no notification needed
            elseif exit_code == 0 then
              notify.info(icons.success .. " " .. label .. " completed in " .. duration)
            else
              notify.error(icons.failure .. " " .. label .. " failed (exit " .. exit_code .. ") in " .. duration)
            end

            local hist_entry = {
              project = project,
              target = target,
              cmd = cmd,
              args = extra_args,
              exit_code = was_killed and -1 or exit_code,
              duration = elapsed,
            }
            history.add(hist_entry)
            history.save()
            fire_task_changed()
          end)
        end,
      })
    end)

    panel.add_buffer(bufnr, label)
    local task_entry = {
      project = project,
      target = target,
      cmd = cmd,
      start_time = start_time,
      buf = bufnr,
    }
    table.insert(running_tasks, task_entry)
    fire_task_changed()

    if config.get().panel.auto_show then
      panel.show()
    end

    return
  end

  -- Short-lived tasks use Snacks.terminal (float by default)
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    notify.error("snacks.nvim is required for the task runner")
    return
  end

  local opts = {
    cwd = root,
    interactive = false,
    auto_close = false,
  }

  local effective_style = cfg.terminal_style
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

  local term = snacks.terminal(cmd, opts)

  local task_entry = {
    project = project,
    target = target,
    cmd = cmd,
    start_time = start_time,
    term = term,
  }
  table.insert(running_tasks, task_entry)
  fire_task_changed()

  if cfg.notify_on_complete and term and term.buf then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = term.buf,
      once = true,
      callback = function()
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
        fire_task_changed()
      end,
    })
  end
end

function M.running_count()
  return #running_tasks
end

--- Mark a buffer as user-killed to suppress failure notifications.
--- @param bufnr number
function M.mark_killed(bufnr)
  user_killed[bufnr] = true
end

--- Check if a specific project:target is currently running.
--- @param project string
--- @param target string
--- @return boolean
function M.is_running(project, target)
  for _, t in ipairs(running_tasks) do
    if t.project == project and t.target == target then
      return true
    end
  end
  return false
end

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
    -- Panel-managed task (has .buf directly)
    if t.buf and vim.api.nvim_buf_is_valid(t.buf) then
      local chan = vim.bo[t.buf].channel
      if chan and chan > 0 then
        vim.fn.jobstop(chan)
      end
    -- Snacks-managed task (has .term.buf)
    elseif t.term and t.term.buf and vim.api.nvim_buf_is_valid(t.term.buf) then
      local chan = vim.bo[t.term.buf].channel
      if chan and chan > 0 then
        vim.fn.jobstop(chan)
      end
    end
  end
  notify.info("Stopped " .. #to_stop .. " task(s)")
end

function M.rerun()
  local entries = history.list()
  if #entries == 0 then
    notify.warn("No previous runs to repeat")
    return
  end
  local last = entries[1]
  M.run(last.project, last.target, last.args)
end

return M
