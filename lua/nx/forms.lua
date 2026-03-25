local config = require("nx.config")
local notify = require("nx.notify")

local M = {}

function M.apply_defaults(fields)
  local result = {}
  for _, f in ipairs(fields) do
    local copy = vim.tbl_extend("force", {}, f)
    if f.default ~= nil then
      copy.value = f.default
    elseif f.type == "boolean" then
      copy.value = false
    elseif f.type == "array" then
      copy.value = {}
    else
      copy.value = ""
    end
    table.insert(result, copy)
  end
  return result
end

function M.build_cli_args(entries)
  local args = {}
  for _, e in ipairs(entries) do
    if e.value ~= nil and e.value ~= "" then
      if type(e.value) == "boolean" then
        if e.value then
          table.insert(args, "--" .. e.name)
        else
          table.insert(args, "--no-" .. e.name)
        end
      elseif type(e.value) == "table" then
        for _, item in ipairs(e.value) do
          if item ~= "" then
            table.insert(args, "--" .. e.name .. "=" .. tostring(item))
          end
        end
      else
        table.insert(args, "--" .. e.name .. "=" .. tostring(e.value))
      end
    end
  end
  return args
end

--- Format a field value for display.
local function format_value(f)
  if f.type == "boolean" then
    return f.value and "yes" or "no"
  elseif f.type == "enum" then
    return tostring(f.value or "")
  elseif f.type == "array" then
    local items = type(f.value) == "table" and f.value or {}
    return table.concat(items, ", ")
  else
    return tostring(f.value or "")
  end
end

--- Render the full form buffer contents with highlights.
local function render_form(popup, fields, current_field)
  local ns = vim.api.nvim_create_namespace("nx_form")
  local lines = {}
  local highlights = {}
  local name_width = 0

  -- Find the longest field name for alignment
  for _, f in ipairs(fields) do
    local label = f.name
    if f.required then label = label .. " *" end
    if #label > name_width then name_width = #label end
  end
  name_width = name_width + 2

  -- Build each field line
  for i, f in ipairs(fields) do
    local label = f.name
    if f.required then label = label .. " *" end
    local padding = string.rep(" ", name_width - #label)

    local value_str = format_value(f)
    if value_str == "" then value_str = "·" end

    local type_hint = ""
    if f.type == "enum" and f.options then
      type_hint = "  (" .. table.concat(f.options, " | ") .. ")"
    elseif f.type == "boolean" then
      type_hint = "  (yes/no)"
    elseif f.type == "number" then
      type_hint = "  (number)"
    end

    local desc = ""
    if f.description and f.description ~= "" then
      desc = "  — " .. f.description
    end

    local line = "  " .. label .. padding .. value_str .. type_hint .. desc
    table.insert(lines, line)

    -- Highlights for this line
    local is_active = (i == current_field)
    local col = 2  -- after leading "  "

    -- Field name highlight
    table.insert(highlights, {
      line = i - 1,
      start = col,
      finish = col + #label,
      hl = f.required and "DiagnosticWarn" or "Identifier",
    })
    col = col + #label + #padding

    -- Value highlight
    table.insert(highlights, {
      line = i - 1,
      start = col,
      finish = col + #value_str,
      hl = is_active and "String" or (value_str == "·" and "NonText" or "Normal"),
    })
    col = col + #value_str

    -- Type hint highlight
    if type_hint ~= "" then
      table.insert(highlights, {
        line = i - 1,
        start = col,
        finish = col + #type_hint,
        hl = "NonText",
      })
      col = col + #type_hint
    end

    -- Description highlight
    if desc ~= "" then
      table.insert(highlights, {
        line = i - 1,
        start = col,
        finish = col + #desc,
        hl = "Comment",
      })
    end
  end

  -- Separator + hints
  table.insert(lines, "")
  table.insert(lines, "  <CR> edit  <Tab>/<S-Tab> navigate  <C-s> submit  q cancel")

  vim.bo[popup.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.bo[popup.bufnr].modifiable = false

  -- Apply highlights
  vim.api.nvim_buf_clear_namespace(popup.bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(popup.bufnr, ns, hl.hl, hl.line, hl.start, hl.finish)
  end
  -- Hints line highlight
  vim.api.nvim_buf_add_highlight(popup.bufnr, ns, "NonText", #fields + 1, 0, -1)
end

function M.open(title, fields, on_submit)
  local ok, Popup = pcall(require, "nui.popup")
  if not ok then
    notify.error("nui.nvim is required for generator forms")
    return
  end

  -- Calculate width based on content
  local max_line = 40
  for _, f in ipairs(fields) do
    local est = #f.name + 4 + #format_value(f) + #(f.description or "") + 20
    if est > max_line then max_line = est end
  end
  local width = math.min(math.max(max_line, 60), 100)
  local height = #fields + 3  -- fields + blank + hints

  local popup = Popup({
    position = "50%",
    size = { width = width, height = height },
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " " .. title .. " ",
        top_align = "center",
        bottom = " <C-s> submit ",
        bottom_align = "right",
      },
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      buftype = "nofile",
      filetype = "nx-form",
    },
    win_options = {
      cursorline = true,
      wrap = false,
    },
  })

  popup:mount()

  local current_field = 1

  local function refresh()
    render_form(popup, fields, current_field)
    -- Position cursor on current field line
    pcall(vim.api.nvim_win_set_cursor, popup.winid, { current_field, 2 })
  end

  local function goto_field(idx)
    if idx < 1 then idx = #fields end
    if idx > #fields then idx = 1 end
    current_field = idx
    refresh()
  end

  --- Refocus the form after an input/select completes or is cancelled.
  local function refocus()
    vim.schedule(function()
      if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
        vim.api.nvim_set_current_win(popup.winid)
        refresh()
      end
    end)
  end

  local function edit_field()
    local f = fields[current_field]
    if not f then return end

    if f.type == "boolean" then
      -- Toggle inline — no popup needed
      f.value = not f.value
      refresh()

    elseif f.type == "enum" and f.options then
      -- Dropdown picker for enum values
      vim.ui.select(f.options, {
        prompt = f.name .. ":",
        format_item = function(item)
          local marker = item == f.value and "● " or "  "
          return marker .. item
        end,
      }, function(choice)
        if choice then
          f.value = choice
        end
        refocus()
      end)

    elseif f.type == "array" then
      local current_val = type(f.value) == "table" and table.concat(f.value, ", ") or ""
      vim.ui.input({ prompt = f.name .. " (comma-separated): ", default = current_val }, function(input)
        if input ~= nil then
          local items = {}
          for item in input:gmatch("[^,]+") do
            table.insert(items, vim.trim(item))
          end
          f.value = items
        end
        refocus()
      end)

    elseif f.type == "number" then
      vim.ui.input({ prompt = f.name .. ": ", default = tostring(f.value or "") }, function(input)
        if input ~= nil then
          local num = tonumber(input)
          if num then
            f.value = num
          else
            notify.warn("'" .. input .. "' is not a valid number")
          end
        end
        refocus()
      end)

    else
      -- String input
      vim.ui.input({ prompt = f.name .. ": ", default = tostring(f.value or "") }, function(input)
        if input ~= nil then
          f.value = input
        end
        refocus()
      end)
    end
  end

  local function submit()
    for _, f in ipairs(fields) do
      if f.required and (f.value == nil or f.value == "") then
        notify.warn("Required field '" .. f.name .. "' is empty")
        return
      end
    end
    popup:unmount()
    on_submit(fields)
  end

  local map_opts = { noremap = true, silent = true }
  popup:map("n", "j", function() goto_field(current_field + 1) end, map_opts)
  popup:map("n", "k", function() goto_field(current_field - 1) end, map_opts)
  popup:map("n", "<Tab>", function() goto_field(current_field + 1) end, map_opts)
  popup:map("n", "<S-Tab>", function() goto_field(current_field - 1) end, map_opts)
  popup:map("n", "<CR>", edit_field, map_opts)
  popup:map("n", "<C-s>", submit, map_opts)
  popup:map("n", "q", function() popup:unmount() end, map_opts)

  refresh()
end

return M
