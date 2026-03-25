local config = require("nx.config")
local projects = require("nx.projects")
local workspace = require("nx.workspace")
local runner = require("nx.runner")
local notify = require("nx.notify")

local M = {}

local state = {
  split = nil,
  tree = nil,
  filter = "",
  all_nodes = nil,  -- unfiltered nodes for search
}

--- Render the header (title + search bar) into the top of the buffer.
--- Returns the line number where the tree should start rendering (1-indexed).
local function render_header(bufnr, sidebar_width)
  local icons = config.get().icons
  local ns = vim.api.nvim_create_namespace("nx_sidebar_header")

  -- Build title line: ──── Nx Explorer ────
  local title_text = " Nx Explorer "
  local rule_char = "─"
  local avail = (sidebar_width or 40) - #title_text
  local left_pad = math.floor(avail / 2)
  local right_pad = avail - left_pad
  local title_line = string.rep(rule_char, math.max(left_pad, 1)) .. title_text .. string.rep(rule_char, math.max(right_pad, 1))

  -- Build search line
  local search_line
  if state.filter ~= "" then
    search_line = "  " .. icons.nx .. " " .. state.filter
  else
    search_line = "  " .. icons.nx .. " / to search..."
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, 2, false, { title_line, search_line })
  vim.bo[bufnr].modifiable = false

  -- Highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, 2)
  vim.api.nvim_buf_add_highlight(bufnr, ns, "Title", 0, 0, -1)
  if state.filter ~= "" then
    vim.api.nvim_buf_add_highlight(bufnr, ns, "String", 1, 0, -1)
  else
    vim.api.nvim_buf_add_highlight(bufnr, ns, "NonText", 1, 0, -1)
  end

  return 3  -- tree starts at line 3 (1-indexed)
end

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
  local sidebar_width = config.get().explorer.width

  local tree_start = render_header(split.bufnr, sidebar_width)

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

  tree:render(tree_start)
  state.tree = tree

  projects.list(function(names)
    if #names == 0 then
      tree:set_nodes({
        NuiTree.Node({ id = "_empty", text = " No projects found", type = "empty" }),
      })
      render_header(split.bufnr, sidebar_width)
      tree:render(tree_start)
      return
    end

    build_tree_nodes(names, function(nodes)
      state.all_nodes = nodes
      tree:set_nodes(nodes)
      for _, node in ipairs(tree:get_nodes()) do
        node:expand()
      end
      render_header(split.bufnr, sidebar_width)
      tree:render(tree_start)
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

  -- Search: / opens filter, <Esc> clears it
  split:map("n", "/", function()
    vim.ui.input({ prompt = "Filter: ", default = state.filter }, function(input)
      if input ~= nil then
        state.filter = input
        M._apply_filter()
      end
      -- Refocus sidebar
      if state.split and state.split.winid and vim.api.nvim_win_is_valid(state.split.winid) then
        vim.api.nvim_set_current_win(state.split.winid)
      end
    end)
  end, { noremap = true, silent = true })

  split:map("n", "<Esc>", function()
    if state.filter ~= "" then
      state.filter = ""
      M._apply_filter()
    end
  end, { noremap = true, silent = true })
end

--- Apply the current filter to the tree.
function M._apply_filter()
  if not state.split or not state.tree or not state.all_nodes then return end
  local NuiTree = require("nui.tree")
  local sidebar_width = config.get().explorer.width

  if state.filter == "" then
    -- Restore all nodes
    state.tree:set_nodes(state.all_nodes)
    for _, node in ipairs(state.tree:get_nodes()) do
      node:expand()
    end
  else
    -- Filter: keep groups that have matching projects/targets
    local pattern = state.filter:lower()
    local filtered = {}
    for _, group_node in ipairs(state.all_nodes) do
      -- Check children (projects) for matches
      local matching_children = {}
      for _, child_id in ipairs(group_node:get_child_ids()) do
        local child = nil
        -- Find the child node in the original tree
        for _, gn in ipairs(state.all_nodes) do
          -- We need to rebuild — NuiTree nodes from all_nodes
          -- Just do a simple text match on the node data
        end
      end
    end

    -- Simpler approach: rebuild filtered nodes
    local projects_mod = require("nx.projects")
    projects_mod.list(function(names)
      local filtered_names = {}
      for _, name in ipairs(names) do
        if name:lower():find(pattern, 1, true) then
          table.insert(filtered_names, name)
        end
      end
      if #filtered_names > 0 then
        build_tree_nodes(filtered_names, function(nodes)
          state.tree:set_nodes(nodes)
          for _, node in ipairs(state.tree:get_nodes()) do
            node:expand()
          end
          render_header(state.split.bufnr, sidebar_width)
          state.tree:render(3)
        end)
      else
        state.tree:set_nodes({
          NuiTree.Node({ id = "_no_match", text = " No matches", type = "empty" }),
        })
        render_header(state.split.bufnr, sidebar_width)
        state.tree:render(3)
      end
    end)
  end

  render_header(state.split.bufnr, sidebar_width)
  state.tree:render(3)
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
      state.all_nodes = nodes
      local sidebar_width = config.get().explorer.width
      render_header(state.split.bufnr, sidebar_width)
      state.tree:render(3)
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
  state.filter = ""

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
