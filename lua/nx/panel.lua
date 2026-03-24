local config = require("nx.config")
local notify = require("nx.notify")

local M = {}

local state = {
  buffers = {},
  active_idx = 0,
  win = nil,
}

--- Update the panel window statusline to show the active task and count.
local function update_title()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  local active_entry = state.buffers[state.active_idx]
  if not active_entry then return end
  local icons = config.get().icons
  local total = #state.buffers
  local idx = state.active_idx
  -- Build the title and escape % characters so statusline doesn't interpret them
  local title = " " .. icons.nx .. " " .. active_entry.label
  if total > 1 then
    title = title .. "  [" .. idx .. "/" .. total .. "]"
  end
  title = title .. "  " .. icons.running
  -- Escape any % for statusline format, then pad right
  local escaped = title:gsub("%%", "%%%%")
  vim.wo[state.win].statusline = escaped .. "%="
end

function M.add_buffer(bufnr, label)
  table.insert(state.buffers, { buf = bufnr, label = label })
  state.active_idx = #state.buffers
  if vim.api.nvim_buf_is_valid(bufnr) then
    local map_opts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set("n", "]t", function() M.next_buffer() end, map_opts)
    vim.keymap.set("n", "[t", function() M.prev_buffer() end, map_opts)
    vim.keymap.set("n", "q", function() M.hide() end, map_opts)
    vim.keymap.set({ "n", "t" }, "<C-c>", function() M.kill_active() end, map_opts)
  end
  update_title()
end

function M.remove_buffer(bufnr)
  for i, entry in ipairs(state.buffers) do
    if entry.buf == bufnr then
      table.remove(state.buffers, i)
      if state.active_idx > #state.buffers then
        state.active_idx = math.max(1, #state.buffers)
      end
      break
    end
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local active = M.get_active()
    if active then
      vim.api.nvim_win_set_buf(state.win, active.buf)
    elseif #state.buffers == 0 then
      M.hide()
    end
  end
end

function M.list_buffers()
  return state.buffers
end

function M.get_active()
  if state.active_idx >= 1 and state.active_idx <= #state.buffers then
    return state.buffers[state.active_idx]
  end
  return nil
end

function M.select_buffer(bufnr)
  for i, entry in ipairs(state.buffers) do
    if entry.buf == bufnr then
      state.active_idx = i
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_set_buf(state.win, bufnr)
      end
      break
    end
  end
  update_title()
end

function M.next_buffer()
  if #state.buffers == 0 then return end
  state.active_idx = (state.active_idx % #state.buffers) + 1
  local active = M.get_active()
  if active and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_buf(state.win, active.buf)
  end
  update_title()
end

function M.prev_buffer()
  if #state.buffers == 0 then return end
  state.active_idx = state.active_idx - 1
  if state.active_idx < 1 then
    state.active_idx = #state.buffers
  end
  local active = M.get_active()
  if active and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_buf(state.win, active.buf)
  end
  update_title()
end

function M._apply_keymaps()
  for _, entry in ipairs(state.buffers) do
    if vim.api.nvim_buf_is_valid(entry.buf) then
      local map_opts = { noremap = true, silent = true, buffer = entry.buf }
      vim.keymap.set("n", "]t", function() M.next_buffer() end, map_opts)
      vim.keymap.set("n", "[t", function() M.prev_buffer() end, map_opts)
      vim.keymap.set("n", "q", function() M.hide() end, map_opts)
      vim.keymap.set({ "n", "t" }, "<C-c>", function() M.kill_active() end, map_opts)
    end
  end
end

function M.show()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  if #state.buffers == 0 then
    notify.warn("No tasks in panel")
    return
  end

  local cfg = config.get().panel
  local active = M.get_active()
  if not active then return end

  if cfg.position == "bottom" then
    vim.cmd("botright " .. cfg.height .. "split")
  else
    vim.cmd("botright " .. cfg.width .. "vsplit")
  end

  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, active.buf)

  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].winfixheight = true
  vim.wo[state.win].winfixwidth = true

  M._apply_keymaps()

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win),
    once = true,
    callback = function()
      state.win = nil
    end,
  })

  update_title()
end

function M.hide()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
  end
  state.win = nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.hide()
  else
    M.show()
  end
end

function M.is_visible()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.pick()
  if #state.buffers == 0 then
    notify.warn("No tasks in panel")
    return
  end

  local ok, snacks = pcall(require, "snacks")
  if not ok then
    notify.error("snacks.nvim is required")
    return
  end

  local icons = config.get().icons
  local items = {}
  for i, entry in ipairs(state.buffers) do
    table.insert(items, {
      text = entry.label,
      entry = entry,
      idx = i,
    })
  end

  snacks.picker({
    title = icons.nx .. " Running Tasks",
    items = items,
    format = function(item, picker)
      return {
        { icons.running .. " ", "Special" },
        { item.entry.label, "Function" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      M.select_buffer(item.entry.buf)
      M.show()
    end,
  })
end

--- Kill the process running in the active panel buffer.
function M.kill_active()
  local active = M.get_active()
  if not active then return end
  if vim.api.nvim_buf_is_valid(active.buf) then
    local chan = vim.bo[active.buf].channel
    if chan and chan > 0 then
      vim.fn.jobstop(chan)
      notify.info("Killed: " .. active.label)
    end
  end
end

function M.reset()
  state.buffers = {}
  state.active_idx = 0
  state.win = nil
end

return M
