local utils = require("nx.utils")
local workspace = require("nx.workspace")
local config = require("nx.config")
local notify = require("nx.notify")

local M = {}

function M.parse_collections(json_str)
  local ok, raw = pcall(vim.json.decode, json_str)
  if not ok or type(raw) ~= "table" then
    return {}
  end

  local collections = {}
  local plugins = raw.plugins or {}
  for _, plugin in ipairs(plugins) do
    local gens = {}
    local caps = plugin.capabilities or {}
    local gen_map = caps.generators or {}
    for name, def in pairs(gen_map) do
      table.insert(gens, {
        name = name,
        description = def.description or "",
      })
    end
    table.sort(gens, function(a, b) return a.name < b.name end)
    if #gens > 0 then
      table.insert(collections, {
        name = plugin.name or "",
        generators = gens,
      })
    end
  end
  return collections
end

function M.parse_schema(json_str)
  local ok, raw = pcall(vim.json.decode, json_str)
  if not ok or type(raw) ~= "table" then
    return {}
  end

  local schema = raw.schema or {}
  local properties = schema.properties or {}
  local required_set = {}
  for _, r in ipairs(schema.required or {}) do
    required_set[r] = true
  end

  local fields = {}
  for name, prop in pairs(properties) do
    local field_type = prop.type or "string"
    if prop.enum then
      field_type = "enum"
    end
    if field_type == "array" then
      field_type = "array"
    end

    table.insert(fields, {
      name = name,
      type = field_type,
      description = prop.description or "",
      default = prop.default,
      required = required_set[name] or false,
      options = prop.enum,
    })
  end

  table.sort(fields, function(a, b)
    if a.required ~= b.required then
      return a.required
    end
    return a.name < b.name
  end)

  return fields
end

function M.list_collections(callback)
  local root = workspace.root()
  if not root then
    notify.warn("No Nx workspace detected")
    callback({})
    return
  end

  local cmd = workspace.nx_cmd({ "list", "--json" })
  utils.exec(cmd, function(stdout)
    local collections = M.parse_collections(stdout)
    callback(collections)
  end, function(err)
    notify.error("Failed to list generators: " .. (err or "unknown"))
    callback({})
  end)
end

function M.get_schema(collection, generator, callback)
  local cmd = workspace.nx_cmd({ "generate", collection .. ":" .. generator, "--help", "--json" })
  utils.exec(cmd, function(stdout)
    local fields = M.parse_schema(stdout)
    callback(fields)
  end, function(err)
    notify.error("Failed to get generator schema: " .. (err or "unknown"))
    callback({})
  end)
end

return M
