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

function M.open(title, fields, on_submit)
  local ok, Popup = pcall(require, "nui.popup")
  if not ok then
    notify.error("nui.nvim is required for generator forms")
    return
  end
  local NuiLine = require("nui.line")

  local width = 60
  local height = math.min(#fields * 3 + 4, 30)

  local popup = Popup({
    position = "50%",
    size = { width = width, height = height },
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = { top = " " .. title .. " ", top_align = "center" },
    },
    buf_options = {
      modifiable = true,
      readonly = false,
      buftype = "nofile",
      filetype = "nx-form",
    },
    win_options = {
      cursorline = true,
      wrap = true,
    },
  })

  popup:mount()

  local lines = {}
  local field_lines = {}
  local current_field = 1

  for i, f in ipairs(fields) do
    local label = f.name
    if f.required then label = label .. " *" end

    table.insert(lines, label .. "  (" .. f.type .. ")")
    local val_display
    if f.type == "boolean" then
      val_display = f.value and "[x] yes" or "[ ] no"
    elseif f.type == "enum" then
      val_display = "> " .. tostring(f.value or "")
      if f.options then
        val_display = val_display .. "  [" .. table.concat(f.options, ", ") .. "]"
      end
    elseif f.type == "array" then
      local items = type(f.value) == "table" and f.value or {}
      val_display = "> [" .. table.concat(items, ", ") .. "]"
    else
      val_display = "> " .. tostring(f.value or "")
    end
    table.insert(lines, "  " .. val_display)
    field_lines[#lines] = i
    table.insert(lines, "  " .. (f.description or ""))
  end

  table.insert(lines, "")
  table.insert(lines, "  <CR> edit field  |  <C-s> submit  |  <Tab>/<S-Tab> navigate  |  q cancel")

  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.bo[popup.bufnr].modifiable = false

  vim.api.nvim_win_set_cursor(popup.winid, { 2, 0 })

  local function field_value_line(idx)
    local line = 1
    for i = 1, idx do
      if i > 1 then line = line + 3 end
    end
    return line + 1
  end

  local function goto_field(idx)
    if idx < 1 then idx = #fields end
    if idx > #fields then idx = 1 end
    current_field = idx
    local target_line = field_value_line(idx)
    vim.api.nvim_win_set_cursor(popup.winid, { target_line, 0 })
  end

  local function edit_field()
    local f = fields[current_field]
    if not f then return end

    if f.type == "boolean" then
      f.value = not f.value
      local val_line = field_value_line(current_field)
      local display = f.value and "  [x] yes" or "  [ ] no"
      vim.bo[popup.bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(popup.bufnr, val_line - 1, val_line, false, { display })
      vim.bo[popup.bufnr].modifiable = false

    elseif f.type == "enum" and f.options then
      local current_idx = 1
      for j, opt in ipairs(f.options) do
        if opt == f.value then current_idx = j end
      end
      current_idx = (current_idx % #f.options) + 1
      f.value = f.options[current_idx]
      local val_line = field_value_line(current_field)
      local display = "  > " .. f.value .. "  [" .. table.concat(f.options, ", ") .. "]"
      vim.bo[popup.bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(popup.bufnr, val_line - 1, val_line, false, { display })
      vim.bo[popup.bufnr].modifiable = false

    elseif f.type == "array" then
      local current_val = type(f.value) == "table" and table.concat(f.value, ", ") or ""
      vim.ui.input({ prompt = f.name .. " (comma-separated): ", default = current_val }, function(input)
        if input ~= nil then
          local items = {}
          for item in input:gmatch("[^,]+") do
            table.insert(items, vim.trim(item))
          end
          f.value = items
          local val_line = field_value_line(current_field)
          local display = "  > [" .. table.concat(items, ", ") .. "]"
          vim.bo[popup.bufnr].modifiable = true
          vim.api.nvim_buf_set_lines(popup.bufnr, val_line - 1, val_line, false, { display })
          vim.bo[popup.bufnr].modifiable = false
        end
      end)

    elseif f.type == "number" then
      vim.ui.input({ prompt = f.name .. " (number): ", default = tostring(f.value or "") }, function(input)
        if input ~= nil then
          local num = tonumber(input)
          if num then
            f.value = num
            local val_line = field_value_line(current_field)
            local display = "  > " .. tostring(num)
            vim.bo[popup.bufnr].modifiable = true
            vim.api.nvim_buf_set_lines(popup.bufnr, val_line - 1, val_line, false, { display })
            vim.bo[popup.bufnr].modifiable = false
          else
            notify.warn("'" .. input .. "' is not a valid number")
          end
        end
      end)

    else
      vim.ui.input({ prompt = f.name .. ": ", default = tostring(f.value or "") }, function(input)
        if input ~= nil then
          f.value = input
          local val_line = field_value_line(current_field)
          local display = "  > " .. input
          vim.bo[popup.bufnr].modifiable = true
          vim.api.nvim_buf_set_lines(popup.bufnr, val_line - 1, val_line, false, { display })
          vim.bo[popup.bufnr].modifiable = false
        end
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
  popup:map("n", "<Tab>", function() goto_field(current_field + 1) end, map_opts)
  popup:map("n", "<S-Tab>", function() goto_field(current_field - 1) end, map_opts)
  popup:map("n", "<CR>", edit_field, map_opts)
  popup:map("n", "<C-s>", submit, map_opts)
  popup:map("n", "q", function() popup:unmount() end, map_opts)
end

return M
