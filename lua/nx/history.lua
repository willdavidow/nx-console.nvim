local config = require("nx.config")

local M = {}

local entries = {}
local history_path = nil

local function get_path()
  if history_path then return history_path end
  return vim.fn.stdpath("data") .. "/nx-history.json"
end

function M._set_path(path)
  history_path = path
end

function M.add(entry)
  entry.timestamp = entry.timestamp or os.time()
  table.insert(entries, 1, entry)
  local max = config.get().history.max_entries
  while #entries > max do
    table.remove(entries)
  end
end

function M.list()
  return entries
end

function M.remove(idx)
  if idx >= 1 and idx <= #entries then
    table.remove(entries, idx)
  end
end

function M.save()
  if not config.get().history.persist then return end
  local path = get_path()
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  local json = vim.fn.json_encode(entries)
  local f = io.open(path, "w")
  if f then
    f:write(json)
    f:close()
  end
end

function M.load()
  local path = get_path()
  if vim.fn.filereadable(path) ~= 1 then return end
  local f = io.open(path, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.fn.json_decode, content)
  if ok and type(decoded) == "table" then
    entries = decoded
  end
end

function M.format_relative_time(timestamp)
  local diff = os.time() - timestamp
  if diff < 60 then
    return diff .. "s ago"
  elseif diff < 3600 then
    return math.floor(diff / 60) .. " min ago"
  elseif diff < 86400 then
    return math.floor(diff / 3600) .. " hr ago"
  else
    return math.floor(diff / 86400) .. "d ago"
  end
end

function M.reset()
  entries = {}
end

--- Open the history picker via Snacks.picker.
function M.picker()
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    require("nx.notify").error("snacks.nvim is required")
    return
  end

  if #entries == 0 then
    require("nx.notify").warn("No run history")
    return
  end

  local icons = config.get().icons
  local items = {}
  for i, entry in ipairs(entries) do
    local label = entry.project .. ":" .. entry.target
    local duration = entry.duration and string.format("%.1fs", entry.duration) or "--"
    local time_ago = M.format_relative_time(entry.timestamp)
    local suffix = entry.exit_code ~= 0 and "  (failed)" or ""
    table.insert(items, {
      text = label .. " " .. duration .. " " .. time_ago .. suffix,
      entry = entry,
      idx = i,
      preview = {
        text = "Command: " .. entry.cmd
          .. "\nProject: " .. entry.project
          .. "\nTarget: " .. entry.target
          .. "\nExit code: " .. (entry.exit_code or "?")
          .. "\nDuration: " .. duration
          .. "\nTime: " .. os.date("%Y-%m-%d %H:%M:%S", entry.timestamp)
          .. (entry.args and ("\nArgs: " .. entry.args) or ""),
      },
    })
  end

  snacks.picker({
    title = icons.nx .. " Nx Run History",
    items = items,
    format = function(item, picker)
      local e = item.entry
      local status_icon = e.exit_code == 0 and icons.success or icons.failure
      local hl = e.exit_code == 0 and "DiagnosticOk" or "DiagnosticError"
      local label = e.project .. ":" .. e.target
      local duration = e.duration and string.format("%.1fs", e.duration) or "--"
      return {
        { status_icon .. " ", hl },
        { label, "Function" },
        { "  " },
        { duration, "Number" },
        { "  " },
        { M.format_relative_time(e.timestamp), "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      local e = item.entry
      require("nx.runner").run(e.project, e.target, e.args)
    end,
    actions = {
      yank_cmd = function(picker, item)
        vim.fn.setreg("+", item.entry.cmd)
        require("nx.notify").info("Yanked: " .. item.entry.cmd)
      end,
      delete_entry = function(picker, item)
        M.remove(item.idx)
        M.save()
        picker:close()
        M.picker()
      end,
      open_output = function(picker, item)
        local e = item.entry
        if e._term_buf and vim.api.nvim_buf_is_valid(e._term_buf) then
          picker:close()
          vim.cmd("buffer " .. e._term_buf)
        else
          require("nx.notify").warn("Terminal output no longer available")
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-y>"] = { "yank_cmd", mode = { "n", "i" }, desc = "Yank command" },
          ["<C-d>"] = { "delete_entry", mode = { "n", "i" }, desc = "Delete entry" },
          ["<C-o>"] = { "open_output", mode = { "n", "i" }, desc = "Open terminal output" },
        },
      },
    },
  })
end

return M
