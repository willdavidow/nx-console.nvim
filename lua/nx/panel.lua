local config = require("nx.config")
local notify = require("nx.notify")

local M = {}

local state = {
  buffers = {},
  active_idx = 0,
  header_buf = nil,   -- 1-line buffer for the title bar
  header_win = nil,   -- window showing the title bar
  win = nil,          -- window showing the terminal content
}

--- Render the title text into the header buffer.
local function render_header()
  if not state.header_buf or not vim.api.nvim_buf_is_valid(state.header_buf) then return end
  local active_entry = state.buffers[state.active_idx]
  if not active_entry then return end
  local icons = config.get().icons
  local total = #state.buffers
  local idx = state.active_idx
  local title = " " .. icons.nx .. " " .. active_entry.label
  if total > 1 then
    title = title .. "  [" .. idx .. "/" .. total .. "]  ]t/[t switch  <C-c> kill"
  end
  title = title .. "  " .. icons.running

  vim.bo[state.header_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.header_buf, 0, -1, false, { title })
  vim.bo[state.header_buf].modifiable = false

  -- Apply highlight to the entire line
  vim.api.nvim_buf_clear_namespace(state.header_buf, -1, 0, -1)
  vim.api.nvim_buf_add_highlight(state.header_buf, -1, "StatusLine", 0, 0, -1)
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
  render_header()
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
      render_header()
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
  render_header()
end

function M.next_buffer()
  if #state.buffers == 0 then return end
  state.active_idx = (state.active_idx % #state.buffers) + 1
  local active = M.get_active()
  if active and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_buf(state.win, active.buf)
  end
  render_header()
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
  render_header()
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

  -- Create a 1-line header buffer for the title bar
  state.header_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.header_buf].bufhidden = "wipe"
  vim.bo[state.header_buf].buflisted = false
  vim.bo[state.header_buf].buftype = "nofile"
  vim.bo[state.header_buf].modifiable = false

  -- Open the main split (header + terminal together)
  -- Total height = config height; header takes 1 line
  local total_height = cfg.position == "bottom" and cfg.height or nil
  local total_width = cfg.position ~= "bottom" and cfg.width or nil

  if cfg.position == "bottom" then
    vim.cmd("botright " .. (total_height + 1) .. "split")
  else
    vim.cmd("botright " .. total_width .. "vsplit")
  end

  -- This window becomes the header (1 line)
  state.header_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.header_win, state.header_buf)
  vim.wo[state.header_win].number = false
  vim.wo[state.header_win].relativenumber = false
  vim.wo[state.header_win].signcolumn = "no"
  vim.wo[state.header_win].cursorline = false
  vim.wo[state.header_win].winfixheight = true
  vim.wo[state.header_win].statusline = " "
  vim.api.nvim_win_set_height(state.header_win, 1)

  -- Open terminal split below the header
  vim.cmd("belowright " .. (total_height and total_height - 1 or "") .. "split")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, active.buf)
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].winfixheight = true
  vim.wo[state.win].winfixwidth = true
  vim.wo[state.win].statusline = " "

  M._apply_keymaps()
  render_header()

  -- Track window close — clean up both windows
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win),
    once = true,
    callback = function()
      state.win = nil
      -- Also close header
      if state.header_win and vim.api.nvim_win_is_valid(state.header_win) then
        vim.api.nvim_win_close(state.header_win, true)
      end
      state.header_win = nil
      state.header_buf = nil
    end,
  })
end

function M.hide()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
  end
  if state.header_win and vim.api.nvim_win_is_valid(state.header_win) then
    vim.api.nvim_win_close(state.header_win, true)
  end
  state.win = nil
  state.header_win = nil
  state.header_buf = nil
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
  state.header_win = nil
  state.header_buf = nil
end

return M
