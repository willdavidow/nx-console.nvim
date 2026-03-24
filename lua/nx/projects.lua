local utils = require("nx.utils")
local workspace = require("nx.workspace")
local notify = require("nx.notify")

local M = {}

local cache = {
  project_names = nil,
  project_details = {},
  fetched_at = nil,
}

--- Parse the JSON output of `nx show projects --json`.
--- @param json_str string
--- @return string[] project names
function M.parse_project_list(json_str)
  local ok, decoded = pcall(vim.json.decode, json_str)
  if not ok or type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

--- Parse the JSON output of `nx show project <name> --json`.
--- @param json_str string
--- @return { name: string, root: string, type: string, targets: { name: string, executor: string }[] }
function M.parse_project_detail(json_str)
  local ok, raw = pcall(vim.json.decode, json_str)
  if not ok or type(raw) ~= "table" then
    return { name = "", root = "", type = "library", targets = {} }
  end

  local targets = {}
  if raw.targets then
    for name, def in pairs(raw.targets) do
      table.insert(targets, {
        name = name,
        executor = def.executor or "",
      })
    end
    table.sort(targets, function(a, b) return a.name < b.name end)
  end

  return {
    name = raw.name or "",
    root = raw.root or "",
    type = raw.projectType or "library",
    targets = targets,
  }
end

--- Fetch all project names asynchronously.
--- @param callback fun(names: string[])
function M.list(callback)
  if cache.project_names then
    callback(cache.project_names)
    return
  end

  local root = workspace.root()
  if not root then
    notify.warn("No Nx workspace detected")
    callback({})
    return
  end

  local cmd = workspace.nx_cmd({ "show", "projects", "--json" })
  utils.exec(cmd, function(stdout)
    local names = M.parse_project_list(stdout)
    cache.project_names = names
    callback(names)
  end, function(err)
    notify.error("Failed to list projects: " .. (err or "unknown error"))
    callback({})
  end)
end

--- Fetch detail for a single project asynchronously.
--- @param name string project name
--- @param callback fun(detail: table)
function M.detail(name, callback)
  if cache.project_details[name] then
    callback(cache.project_details[name])
    return
  end

  local cmd = workspace.nx_cmd({ "show", "project", name, "--json" })
  utils.exec(cmd, function(stdout)
    local detail = M.parse_project_detail(stdout)
    cache.project_details[name] = detail
    callback(detail)
  end, function(err)
    notify.error("Failed to get project " .. name .. ": " .. (err or "unknown error"))
    callback({ name = name, root = "", type = "library", targets = {} })
  end)
end

--- Clear all cached data.
function M.reset()
  cache.project_names = nil
  cache.project_details = {}
  cache.fetched_at = nil
end

return M
