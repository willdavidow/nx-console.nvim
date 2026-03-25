local config = require("nx.config")
local notify = require("nx.notify")

local M = {}

local state = {
  buffers = {},
  active_idx = 0,
  win = nil,           -- terminal split window
  tab_buf = nil,       -- floating tab bar buffer
  tab_win = nil,       -- floating tab bar window (non-focusable)
}

--- Build tab bar content and render into the tab buffer.
local function render_tab_bar()
  if not state.tab_buf or not vim.api.nvim_buf_is_valid(state.tab_buf) then return end
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end

  local icons = config.get().icons
  local parts = {}
  local highlights = {}
  local col = 0

  -- Build tab-style segments: " ● label " for each buffer
  for i, entry in ipairs(state.buffers) do
    local is_active = (i == state.active_idx)
    local segment = " " .. icons.running .. " " .. entry.label .. " "
    table.insert(parts, segment)
    local hl = is_active and "TabLineSel" or "TabLine"
    table.insert(highlights, { hl = hl, start = col, finish = col + #segment })
    col = col + #segment

    if i < #state.buffers then
      local sep = "│"
      table.insert(parts, sep)
      table.insert(highlights, { hl = "TabLineFill", start = col, finish = col + #sep })
      col = col + #sep
    end
  end

  -- Keybind hints on the right side
  local hints = "  ]t/[t switch  <C-c> kill  q hide"
  local padding_needed = vim.api.nvim_win_get_width(state.win) - col - #hints
  if padding_needed > 0 then
    local fill = string.rep(" ", padding_needed)
    table.insert(parts, fill)
    table.insert(highlights, { hl = "TabLineFill", start = col, finish = col + #fill })
    col = col + #fill
  end
  table.insert(parts, hints)
  table.insert(highlights, { hl = "TabLineFill", start = col, finish = col + #hints })

  local line = table.concat(parts)

  vim.bo[state.tab_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.tab_buf, 0, -1, false, { line })
  vim.bo[state.tab_buf].modifiable = false

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("nx_panel_tab")
  vim.api.nvim_buf_clear_namespace(state.tab_buf, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.tab_buf, ns, hl.hl, 0, hl.start, hl.finish)
  end

  -- Resize float to match panel width
  if state.tab_win and vim.api.nvim_win_is_valid(state.tab_win) then
    vim.api.nvim_win_set_config(state.tab_win, {
      relative = "win",
      win = state.win,
      width = vim.api.nvim_win_get_width(state.win),
      height = 1,
      row = 0,
      col = 0,
    })
  end
end

--- Create the floating tab bar anchored to the top of the panel window.
local function create_tab_bar()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end

  state.tab_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.tab_buf].bufhidden = "wipe"
  vim.bo[state.tab_buf].buflisted = false
  vim.bo[state.tab_buf].buftype = "nofile"
  vim.bo[state.tab_buf].modifiable = false

  state.tab_win = vim.api.nvim_open_win(state.tab_buf, false, {
    relative = "win",
    win = state.win,
    row = 0,
    col = 0,
    width = vim.api.nvim_win_get_width(state.win),
    height = 1,
    focusable = false,
    zindex = 50,
    style = "minimal",
  })

  -- Match tabline look
  vim.wo[state.tab_win].winhighlight = "Normal:TabLineFill"

  render_tab_bar()
end

--- Destroy the floating tab bar.
local function destroy_tab_bar()
  if state.tab_win and vim.api.nvim_win_is_valid(state.tab_win) then
    vim.api.nvim_win_close(state.tab_win, true)
  end
  state.tab_win = nil
  state.tab_buf = nil
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
  render_tab_bar()
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
      render_tab_bar()
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
  render_tab_bar()
end

function M.next_buffer()
  if #state.buffers == 0 then return end
  state.active_idx = (state.active_idx % #state.buffers) + 1
  local active = M.get_active()
  if active and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_buf(state.win, active.buf)
  end
  render_tab_bar()
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
  render_tab_bar()
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
  create_tab_bar()

  -- Resize the tab bar when the panel resizes
  vim.api.nvim_create_autocmd("WinResized", {
    group = vim.api.nvim_create_augroup("NxPanelResize", { clear = true }),
    callback = function()
      render_tab_bar()
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win),
    once = true,
    callback = function()
      destroy_tab_bar()
      state.win = nil
      pcall(vim.api.nvim_del_augroup_by_name, "NxPanelResize")
    end,
  })
end

function M.hide()
  destroy_tab_bar()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
  end
  state.win = nil
  pcall(vim.api.nvim_del_augroup_by_name, "NxPanelResize")
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

--- Kill the active process and close its tab.
--- If it was the last tab, closes the entire panel.
function M.kill_active()
  local active = M.get_active()
  if not active then return end
  local bufnr = active.buf
  local label = active.label

  -- Mark as user-killed so runner suppresses the failure notification
  require("nx.runner").mark_killed(bufnr)

  -- Kill the process
  if vim.api.nvim_buf_is_valid(bufnr) then
    local chan = vim.bo[bufnr].channel
    if chan and chan > 0 then
      vim.fn.jobstop(chan)
    end
  end

  -- Remove the buffer from the panel
  M.remove_buffer(bufnr)

  -- Clean up the terminal buffer
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end

  -- If no tabs left, hide closes the panel (remove_buffer already calls hide)
  -- If tabs remain, remove_buffer already switched to the next one
  notify.info("Killed: " .. label)
end

function M.reset()
  state.buffers = {}
  state.active_idx = 0
  state.win = nil
  state.tab_buf = nil
  state.tab_win = nil
end

return M
