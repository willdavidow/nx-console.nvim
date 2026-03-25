local utils = require("nx.utils")
local workspace = require("nx.workspace")
local config = require("nx.config")
local notify = require("nx.notify")

local M = {}

--- Parse the text output of `nx list` to extract plugin names that have generators.
--- @param text string raw stdout from `nx list`
--- @return string[] plugin names
function M.parse_plugin_names(text)
  local names = {}
  local in_available = false
  for line in text:gmatch("[^\r\n]+") do
    -- Stop collecting when we hit "Also available" (not-installed plugins)
    if line:find("Also available") then
      in_available = true
    end
    if not in_available then
      -- Lines like: "@nx/eslint (executors,generators)" or "@magnus/plugin (generators)"
      -- Real nx output has no leading whitespace, but be flexible
      local name, caps = line:match("^%s*(%S+)%s+%((.-)%)")
      if name and caps and caps:find("generators") then
        table.insert(names, name)
      end
    end
  end
  return names
end

--- Parse the text output of `nx list <plugin>` to extract generator entries.
--- @param text string raw stdout from `nx list <plugin>`
--- @param plugin_name string the plugin name for context
--- @return table[] generators: { name, description, collection }
function M.parse_plugin_generators(text, plugin_name)
  local gens = {}
  local in_generators = false
  for line in text:gmatch("[^\r\n]+") do
    -- Detect the GENERATORS section header
    if line:match("^%s*GENERATORS") then
      in_generators = true
    elseif line:match("^%s*EXECUTORS") or line:match("^%s*BUILDERS") then
      in_generators = false
    elseif in_generators then
      -- Lines like: "  component : Create a React component"
      -- or:         "  application : Create an application"
      -- Flexible: "component : desc" or "  component : desc"
      local name, desc = line:match("^%s*(%S+)%s+:%s+(.*)")
      if name then
        table.insert(gens, {
          name = name,
          description = vim.trim(desc or ""),
          collection = plugin_name,
        })
      end
    end
  end
  return gens
end

--- Parse JSON collection format as fallback (for nx list --json if it works).
--- @param json_str string
--- @return table[] collections
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
    local gen_data = caps.generators or {}

    if #gen_data > 0 then
      for _, name in ipairs(gen_data) do
        if type(name) == "string" then
          table.insert(gens, { name = name, description = "" })
        end
      end
    else
      for name, def in pairs(gen_data) do
        local desc = ""
        if type(def) == "table" then
          desc = def.description or ""
        end
        table.insert(gens, { name = name, description = desc })
      end
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

--- Parse JSON schema format (if available).
--- @param json_str string
--- @return table[] fields
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

--- Parse the text output of `nx generate <col>:<gen> --help` into fields.
--- Handles lines like:
---   --compiler       Description text      [string] [choices: "a", "b"] [default: "a"]
---   --includeVitest  Description text                                           [boolean]
--- @param text string raw help text
--- @return table[] fields
function M.parse_help_text(text)
  local fields = {}
  local in_options = false
  local current_field = nil

  for line in text:gmatch("[^\r\n]+") do
    -- Detect the Options section
    if line:match("^Options:") then
      in_options = true
    elseif in_options then
      -- New option line: starts with whitespace + --name
      local name = line:match("^%s+%-%-(%S+)")
      if name then
        -- Finish previous field
        if current_field then
          table.insert(fields, current_field)
        end

        -- Collect all the text after the flag name
        local rest = line:match("^%s+%-%-" .. name:gsub("%-", "%%-") .. "%s+(.*)")
        rest = rest or ""

        -- Parse type from [string], [boolean], [number], [array]
        -- Must match standalone [type] not inside [choices:...] or [default:...]
        local field_type = rest:match("%[(%w+)%]") or "string"
        if field_type == "count" then field_type = "number" end

        -- Parse choices — may be on this line (complete or start of multi-line)
        local choices_str = rest:match('%[choices:%s*(.*)')
        local options = nil
        if choices_str then
          options = {}
          for choice in choices_str:gmatch('"([^"]+)"') do
            table.insert(options, choice)
          end
          if #options > 0 then
            field_type = "enum"
          end
        end

        -- Parse default: [default: "value"] or [default: true]
        local default_val = rest:match('%[default:%s*"([^"]*)"%]')
          or rest:match('%[default:%s*(%S+)%]')
        if default_val == "true" then default_val = true
        elseif default_val == "false" then default_val = false
        elseif default_val and tonumber(default_val) then default_val = tonumber(default_val)
        end

        -- Extract description: everything before the first [
        local desc = rest:match("^(.-)%s*%[") or rest
        desc = vim.trim(desc)

        current_field = {
          name = name,
          type = field_type,
          description = desc,
          default = default_val,
          required = false,
          options = options,
        }
      elseif current_field then
        -- Continuation line: may contain more choices, defaults, or description text
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
          -- Extract any quoted values (choices continued from previous line)
          if current_field.options then
            for choice in trimmed:gmatch('"([^"]+)"') do
              -- Avoid duplicates
              local exists = false
              for _, o in ipairs(current_field.options) do
                if o == choice then exists = true end
              end
              if not exists then
                table.insert(current_field.options, choice)
              end
            end
            if #current_field.options > 0 then
              current_field.type = "enum"
            end
          end
          -- Check for new choices block starting on this line
          if not current_field.options then
            local new_choices = trimmed:match('%[choices:%s*(.*)')
            if new_choices then
              current_field.options = {}
              for choice in new_choices:gmatch('"([^"]+)"') do
                table.insert(current_field.options, choice)
              end
              if #current_field.options > 0 then
                current_field.type = "enum"
              end
            end
          end
          -- Parse default
          local cont_default = trimmed:match('%[default:%s*"([^"]*)"%]')
            or trimmed:match('%[default:%s*(%S+)%]')
          if cont_default then
            if cont_default == "true" then current_field.default = true
            elseif cont_default == "false" then current_field.default = false
            elseif tonumber(cont_default) then current_field.default = tonumber(cont_default)
            else current_field.default = cont_default end
          end
          -- Append to description if it's actual text (not metadata)
          local desc_part = trimmed:match("^(.-)%s*%[") or trimmed
          desc_part = vim.trim(desc_part)
          if desc_part ~= "" and not desc_part:match("^%[") and not desc_part:match('^"') then
            if current_field.description ~= "" then
              current_field.description = current_field.description .. " " .. desc_part
            else
              current_field.description = desc_part
            end
          end
        end
      end
    end
  end

  -- Don't forget the last field
  if current_field then
    table.insert(fields, current_field)
  end

  -- Sort: required first, then alphabetical
  table.sort(fields, function(a, b)
    if a.required ~= b.required then
      return a.required
    end
    return a.name < b.name
  end)

  return fields
end

--- Fetch all generators as a flat list: discover plugins, then query each for generators.
--- @param callback fun(generators: table[]) each entry has { name, description, collection }
function M.list_all(callback)
  local root = workspace.root()
  if not root then
    notify.warn("No Nx workspace detected")
    callback({})
    return
  end

  -- Step 1: Get plugin names from `nx list` (text output)
  local cmd = workspace.nx_cmd({ "list" })
  utils.exec(cmd, function(stdout)
    local plugin_names = M.parse_plugin_names(stdout)
    if #plugin_names == 0 then
      notify.warn("No plugins with generators found")
      callback({})
      return
    end

    -- Step 2: Query each plugin for its generators
    local all_generators = {}
    local pending = #plugin_names
    for _, pname in ipairs(plugin_names) do
      local detail_cmd = workspace.nx_cmd({ "list", pname })
      utils.exec(detail_cmd, function(detail_stdout)
        local gens = M.parse_plugin_generators(detail_stdout, pname)
        vim.list_extend(all_generators, gens)
        pending = pending - 1
        if pending == 0 then
          -- Sort: local plugins first (no @), then alphabetical
          table.sort(all_generators, function(a, b)
            local a_is_scoped = a.collection:sub(1, 1) == "@"
            local b_is_scoped = b.collection:sub(1, 1) == "@"
            if a_is_scoped ~= b_is_scoped then
              return not a_is_scoped -- local (unscoped) first
            end
            if a.collection ~= b.collection then
              return a.collection < b.collection
            end
            return a.name < b.name
          end)
          callback(all_generators)
        end
      end, function()
        -- If a plugin query fails, just skip it
        pending = pending - 1
        if pending == 0 then
          callback(all_generators)
        end
      end)
    end
  end, function(err)
    notify.error("Failed to list plugins: " .. (err or "unknown"))
    callback({})
  end)
end

function M.get_schema(collection, generator, callback)
  local cmd = workspace.nx_cmd({ "generate", collection .. ":" .. generator, "--help" })
  utils.exec(cmd, function(stdout)
    -- Try JSON first (some Nx versions), fall back to text parsing
    local fields = M.parse_schema(stdout)
    if #fields == 0 then
      fields = M.parse_help_text(stdout)
    end
    callback(fields)
  end, function(err)
    notify.error("Failed to get generator schema: " .. (err or "unknown"))
    callback({})
  end)
end

--- Open a single flat picker showing all generators, like VS Code Nx Console.
function M.pick()
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    notify.error("snacks.nvim is required")
    return
  end

  local icons = config.get().icons
  notify.info("Loading generators...")

  M.list_all(function(generators)
    if #generators == 0 then
      notify.warn("No generators found")
      return
    end

    local items = {}
    for _, gen in ipairs(generators) do
      local full_name = gen.collection .. ":" .. gen.name
      local is_local = gen.collection:sub(1, 1) ~= "@"
      table.insert(items, {
        text = full_name .. " " .. gen.description,
        generator = gen,
        full_name = full_name,
        is_local = is_local,
        preview = {
          text = "Generator: " .. full_name
            .. "\nPlugin: " .. gen.collection
            .. (is_local and "\nType: Local workspace generator" or "\nType: Plugin generator")
            .. "\n\n" .. gen.description
            .. "\n\nRun: nx generate " .. full_name,
        },
      })
    end

    snacks.picker({
      title = icons.nx .. " Generators",
      items = items,
      format = function(item, picker)
        local g = item.generator
        local tag = item.is_local and "[local] " or ""
        return {
          { icons.target .. " ", "Special" },
          { tag, "Keyword" },
          { g.collection .. ":", "Comment" },
          { g.name, "Function" },
          { "  " },
          { g.description, "Comment" },
        }
      end,
      confirm = function(picker, item)
        picker:close()
        M._open_form(item.generator.collection, item.generator.name)
      end,
    })
  end)
end

function M._open_form(collection_name, generator_name)
  local forms = require("nx.forms")
  local cfg = config.get().generators

  M.get_schema(collection_name, generator_name, function(fields)
    if #fields == 0 then
      notify.warn("No fields found for " .. collection_name .. ":" .. generator_name)
      return
    end

    -- Add a built-in dry-run toggle at the end
    table.insert(fields, {
      name = "dryRun",
      type = "boolean",
      description = "Preview changes without writing to disk",
      default = false,
      required = false,
    })

    local form_fields = forms.apply_defaults(fields)
    local title = "nx generate " .. collection_name .. ":" .. generator_name

    forms.open(title, form_fields, function(completed_fields)
      -- Extract and remove the dryRun field before building args
      local dry_run = false
      local gen_fields = {}
      for _, f in ipairs(completed_fields) do
        if f.name == "dryRun" then
          dry_run = f.value
        else
          table.insert(gen_fields, f)
        end
      end

      local args = forms.build_cli_args(gen_fields)
      if dry_run then
        table.insert(args, "--dry-run")
      end

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
