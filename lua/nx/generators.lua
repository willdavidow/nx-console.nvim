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

function M.pick()
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    notify.error("snacks.nvim is required")
    return
  end

  local icons = config.get().icons

  M.list_collections(function(collections)
    if #collections == 0 then
      notify.warn("No generator collections found")
      return
    end

    local items = {}
    for _, col in ipairs(collections) do
      table.insert(items, {
        text = col.name .. " (" .. #col.generators .. " generators)",
        collection = col,
        preview = {
          text = "Collection: " .. col.name .. "\n\nGenerators:\n"
            .. table.concat(
              vim.tbl_map(function(g) return "  " .. icons.target .. " " .. g.name .. "  " .. g.description end, col.generators),
              "\n"
            ),
        },
      })
    end

    snacks.picker({
      title = icons.nx .. " Generator Collections",
      items = items,
      format = function(item, picker)
        return {
          { item.collection.name, "Function" },
          { "  " },
          { #item.collection.generators .. " generators", "Comment" },
        }
      end,
      confirm = function(picker, item)
        picker:close()
        M._pick_generator(item.collection)
      end,
    })
  end)
end

function M._pick_generator(collection)
  local ok, snacks = pcall(require, "snacks")
  if not ok then return end

  local icons = config.get().icons
  local items = {}
  for _, gen in ipairs(collection.generators) do
    table.insert(items, {
      text = gen.name .. " " .. gen.description,
      generator = gen,
      preview = {
        text = "Generator: " .. collection.name .. ":" .. gen.name
          .. "\n\n" .. gen.description
          .. "\n\nRun: nx generate " .. collection.name .. ":" .. gen.name,
      },
    })
  end

  snacks.picker({
    title = icons.nx .. " " .. collection.name .. " generators",
    items = items,
    format = function(item, picker)
      return {
        { icons.target .. " ", "Special" },
        { item.generator.name, "Function" },
        { "  " },
        { item.generator.description, "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      M._open_form(collection.name, item.generator.name)
    end,
  })
end

function M._open_form(collection_name, generator_name)
  local forms = require("nx.forms")
  local cfg = config.get().generators

  M.get_schema(collection_name, generator_name, function(fields)
    if #fields == 0 then
      notify.warn("No fields found for " .. collection_name .. ":" .. generator_name)
      return
    end

    local form_fields = forms.apply_defaults(fields)
    local title = "nx generate " .. collection_name .. ":" .. generator_name

    forms.open(title, form_fields, function(completed_fields)
      local args = forms.build_cli_args(completed_fields)

      if cfg.confirm_before_run then
        local cmd_preview = workspace.nx_bin() .. " generate " .. collection_name .. ":" .. generator_name
        for _, arg in ipairs(args) do
          cmd_preview = cmd_preview .. " " .. arg
        end
        vim.ui.select({ "Run", "Cancel" }, {
          prompt = cmd_preview .. "\n\nProceed?",
        }, function(choice)
          if choice == "Run" then
            M._execute(collection_name, generator_name, args)
          end
        end)
      else
        M._execute(collection_name, generator_name, args)
      end
    end)
  end)
end

function M._execute(collection_name, generator_name, args)
  local root = workspace.root()
  if not root then return end

  local cmd_parts = { "generate", collection_name .. ":" .. generator_name }
  vim.list_extend(cmd_parts, args)
  local cmd = workspace.nx_bin()
  for _, part in ipairs(cmd_parts) do
    cmd = cmd .. " " .. part
  end

  local ok, snacks = pcall(require, "snacks")
  if ok then
    snacks.terminal(cmd, {
      cwd = root,
      interactive = false,
      auto_close = false,
      win = {
        style = "terminal",
        position = "float",
        width = 0.8,
        height = 0.7,
        title = " " .. config.get().icons.nx .. " " .. cmd .. " ",
        border = "rounded",
      },
    })
  end
end

return M
