local config = require("nx.config")
local projects = require("nx.projects")
local workspace = require("nx.workspace")
local runner = require("nx.runner")
local notify = require("nx.notify")

local M = {}

local state = {
  split = nil,
  tree = nil,
}

local function build_tree_nodes(project_names, callback)
  local NuiTree = require("nui.tree")
  local pending = #project_names
  local project_details = {}

  for _, name in ipairs(project_names) do
    projects.detail(name, function(detail)
      table.insert(project_details, detail)
      pending = pending - 1
      if pending == 0 then
        local apps = {}
        local libs = {}
        for _, d in ipairs(project_details) do
          if d.type == "application" then
            table.insert(apps, d)
          else
            table.insert(libs, d)
          end
        end
        table.sort(apps, function(a, b) return a.name < b.name end)
        table.sort(libs, function(a, b) return a.name < b.name end)

        local icons = config.get().icons

        local function make_project_node(detail)
          local target_nodes = {}
          local has_running = false
          for _, tgt in ipairs(detail.targets) do
            local is_running = runner.is_running(detail.name, tgt.name)
            if is_running then has_running = true end
            local tgt_icon = is_running and icons.running or icons.target
            table.insert(target_nodes, NuiTree.Node({
              id = detail.name .. ":" .. tgt.name,
              text = tgt_icon .. " " .. tgt.name,
              type = "target",
              project = detail.name,
              target = tgt.name,
              executor = tgt.executor,
              is_running = is_running,
            }))
          end
          local pi = detail.type == "application" and icons.app or icons.lib
          local project_text = pi .. " " .. detail.name
          if has_running then
            project_text = project_text .. " " .. icons.running
          end
          return NuiTree.Node({
            id = detail.name,
            text = project_text,
            type = "project",
            project = detail.name,
            root = detail.root,
            has_running = has_running,
          }, target_nodes)
        end

        local nodes = {}
        if #apps > 0 then
          local app_children = {}
          for _, d in ipairs(apps) do
            table.insert(app_children, make_project_node(d))
          end
          table.insert(nodes, NuiTree.Node({
            id = "_apps",
            text = icons.app .. " apps",
            type = "group",
          }, app_children))
        end
        if #libs > 0 then
          local lib_children = {}
          for _, d in ipairs(libs) do
            table.insert(lib_children, make_project_node(d))
          end
          table.insert(nodes, NuiTree.Node({
            id = "_libs",
            text = icons.lib .. " libs",
            type = "group",
          }, lib_children))
        end

        callback(nodes)
      end
    end)
  end
end

local function setup_tree(split)
  local NuiTree = require("nui.tree")
  local NuiLine = require("nui.line")
  local icons = config.get().icons

  local tree = NuiTree({
    bufnr = split.bufnr,
    prepare_node = function(node)
      local line = NuiLine()
      local indent = string.rep("  ", node:get_depth() - 1)
      line:append(indent)

      if node:has_children() then
        line:append(node:is_expanded() and " " or " ", "NonText")
      else
        line:append("  ")
      end

      if node.type == "group" then
        line:append(node.text, "Title")
      elseif node.type == "project" then
        line:append(node.text, node.has_running and "DiagnosticOk" or "Function")
      elseif node.type == "target" then
        line:append(node.text, node.is_running and "DiagnosticOk" or "Special")
      else
        line:append(node.text)
      end

      return line
    end,
    nodes = {
      NuiTree.Node({ id = "_loading", text = " Loading...", type = "loading" }),
    },
  })

  tree:render()
  state.tree = tree

  projects.list(function(names)
    if #names == 0 then
      tree:set_nodes({
        NuiTree.Node({ id = "_empty", text = " No projects found", type = "empty" }),
      })
      tree:render()
      return
    end

    build_tree_nodes(names, function(nodes)
      tree:set_nodes(nodes)
      for _, node in ipairs(tree:get_nodes()) do
        node:expand()
      end
      tree:render()
    end)
  end)

  return tree
end

local function setup_keymaps(split, tree_fn)
  split:map("n", "<CR>", function()
    local tree = tree_fn()
    if not tree then return end
    local node = tree:get_node()
    if not node then return end

    if node.type == "target" then
      runner.run(node.project, node.target)
    elseif node:has_children() then
      if node:is_expanded() then
        node:collapse()
      else
        node:expand()
      end
      tree:render()
    end
  end, { noremap = true, silent = true })

  split:map("n", "<C-r>", function()
    local tree = tree_fn()
    if not tree then return end
    local node = tree:get_node()
    if not node or node.type ~= "target" then return end
    vim.ui.input({ prompt = "Extra args: " }, function(input)
      if input then
        runner.run(node.project, node.target, input)
      end
    end)
  end, { noremap = true, silent = true })

  split:map("n", "gd", function()
    local tree = tree_fn()
    if not tree then return end
    local node = tree:get_node()
    if not node then return end
    local project_node = node
    while project_node and project_node.type ~= "project" do
      local parent_id = project_node:get_parent_id()
      if parent_id then
        project_node = tree:get_node(parent_id)
      else
        break
      end
    end
    if project_node and project_node.root then
      local root = workspace.root()
      if root then
        vim.cmd("edit " .. root .. "/" .. project_node.root)
      end
    end
  end, { noremap = true, silent = true })

  split:map("n", "gp", function()
    local tree = tree_fn()
    if not tree then return end
    local node = tree:get_node()
    if not node then return end
    local project_node = node
    while project_node and project_node.type ~= "project" do
      local parent_id = project_node:get_parent_id()
      if parent_id then
        project_node = tree:get_node(parent_id)
      else
        break
      end
    end
    if project_node and project_node.root then
      local root = workspace.root()
      if root then
        local pjson = root .. "/" .. project_node.root .. "/project.json"
        if vim.fn.filereadable(pjson) == 1 then
          vim.cmd("edit " .. pjson)
        else
          notify.warn("No project.json found at " .. pjson)
        end
      end
    end
  end, { noremap = true, silent = true })

  split:map("n", "r", function()
    projects.reset()
    local tree = setup_tree(split)
    state.tree = tree
  end, { noremap = true, silent = true })

  split:map("n", "q", function()
    M.close()
  end, { noremap = true, silent = true })
end

--- Refresh the sidebar tree, preserving expand/collapse state.
function M.refresh()
  if not state.split or not state.tree then return end

  -- Capture which nodes are currently expanded
  local expanded = {}
  local function collect_expanded(node_ids, parent_id)
    local nodes = state.tree:get_nodes(parent_id)
    for _, node in ipairs(nodes) do
      if node:is_expanded() then
        expanded[node:get_id()] = true
      end
      if node:has_children() then
        collect_expanded(expanded, node:get_id())
      end
    end
  end
  collect_expanded(expanded, nil)

  -- Rebuild tree nodes
  local NuiTree = require("nui.tree")
  projects.list(function(names)
    if #names == 0 then return end
    build_tree_nodes(names, function(nodes)
      state.tree:set_nodes(nodes)
      -- Re-expand previously expanded nodes
      local function restore_expanded(parent_id)
        local tree_nodes = state.tree:get_nodes(parent_id)
        for _, node in ipairs(tree_nodes) do
          if expanded[node:get_id()] then
            node:expand()
          end
          if node:has_children() then
            restore_expanded(node:get_id())
          end
        end
      end
      restore_expanded(nil)
      state.tree:render()
    end)
  end)
end

function M.open()
  if state.split then
    if state.split.winid and vim.api.nvim_win_is_valid(state.split.winid) then
      vim.api.nvim_set_current_win(state.split.winid)
      return
    end
  end

  local root = workspace.root()
  if not root then
    notify.warn("No Nx workspace detected")
    return
  end

  local ok, Split = pcall(require, "nui.split")
  if not ok then
    notify.error("nui.nvim is required for the sidebar")
    return
  end

  local cfg = config.get().explorer
  local split = Split({
    relative = "editor",
    position = cfg.side,
    size = cfg.width,
    enter = true,
    buf_options = {
      bufhidden = "hide",
      buflisted = false,
      buftype = "nofile",
      swapfile = false,
      filetype = "nx-explorer",
    },
    win_options = {
      number = false,
      relativenumber = false,
      signcolumn = "no",
      cursorline = true,
      wrap = false,
    },
  })

  split:mount()
  state.split = split

  -- Set sidebar title via winbar
  local icons = config.get().icons
  vim.wo[split.winid].winbar = " " .. icons.nx .. " Nx Explorer"

  local tree = setup_tree(split)
  setup_keymaps(split, function() return state.tree end)

  -- Auto-refresh sidebar when task state changes
  vim.api.nvim_create_autocmd("User", {
    pattern = "NxTaskChanged",
    group = vim.api.nvim_create_augroup("NxSidebarRefresh", { clear = true }),
    callback = function()
      if state.split and state.tree then
        M.refresh()
      end
    end,
  })
end

function M.close()
  if state.split then
    state.split:unmount()
    state.split = nil
    state.tree = nil
  end
  -- Stop listening for task changes
  pcall(vim.api.nvim_del_augroup_by_name, "NxSidebarRefresh")
end

function M.toggle()
  if state.split and state.split.winid and vim.api.nvim_win_is_valid(state.split.winid) then
    M.close()
  else
    M.open()
  end
end

return M
