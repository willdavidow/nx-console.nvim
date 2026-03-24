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

return M
