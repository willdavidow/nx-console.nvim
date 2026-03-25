local config = require("nx.config")
local projects = require("nx.projects")
local workspace = require("nx.workspace")
local runner = require("nx.runner")
local notify = require("nx.notify")

local M = {}

local state = {
  picker = nil,
  collapsed = nil,  -- set of item IDs that are collapsed (nil = not initialized yet)
}

--- Ensure collapsed state is initialized (everything collapsed by default).
--- @param project_details table[]
local function init_collapsed(project_details)
  if state.collapsed then return end
  state.collapsed = {}
  state.collapsed["_group_apps"] = true
  state.collapsed["_group_libs"] = true
  for _, d in ipairs(project_details) do
    state.collapsed[d.name] = true
  end
end

--- Build a flat list of picker items with parent references for tree rendering.
--- @param callback fun(items: table[])
local function build_items(callback)
  projects.list(function(names)
    if #names == 0 then
      callback({})
      return
    end

    local pending = #names
    local project_details = {}

    for _, name in ipairs(names) do
      projects.detail(name, function(detail)
        table.insert(project_details, detail)
        pending = pending - 1
        if pending == 0 then
          -- Group by type
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

          -- Initialize collapsed state on first load (everything collapsed)
          init_collapsed(project_details)

          local icons = config.get().icons
          local items = {}
          local idx = 0

          local function add_group(group_name, group_icon, group_projects, is_last_group)
            if #group_projects == 0 then return end
            idx = idx + 1
            local group_id = "_group_" .. group_name
            local is_collapsed = state.collapsed[group_id]
            local collapse_icon = is_collapsed and " " or " "
            local group_item = {
              idx = idx,
              text = collapse_icon .. group_icon .. " " .. group_name,
              item_type = "group",
              group_name = group_name,
              node_id = group_id,
              last = is_last_group,
            }
            table.insert(items, group_item)

            -- Skip children if group is collapsed
            if is_collapsed then return end

            for pi_idx, detail in ipairs(group_projects) do
              idx = idx + 1
              local is_last_project = (pi_idx == #group_projects)
              local project_id = detail.name
              local proj_collapsed = state.collapsed[project_id]
              local has_running = false
              for _, tgt in ipairs(detail.targets) do
                if runner.is_running(detail.name, tgt.name) then
                  has_running = true
                  break
                end
              end

              local pi = detail.type == "application" and icons.app or icons.lib
              local collapse_pi = proj_collapsed and " " or " "
              local project_text = collapse_pi .. pi .. " " .. detail.name
              if has_running then
                project_text = project_text .. " " .. icons.running
              end

              local project_item = {
                idx = idx,
                text = project_text,
                item_type = "project",
                project_name = detail.name,
                project_root = detail.root,
                has_running = has_running,
                node_id = project_id,
                parent = group_item,
                last = is_last_project,
              }
              table.insert(items, project_item)

              -- Skip children if project is collapsed
              if proj_collapsed then goto continue end

              for tgt_idx, tgt in ipairs(detail.targets) do
                idx = idx + 1
                local is_last_target = (tgt_idx == #detail.targets)
                local is_running = runner.is_running(detail.name, tgt.name)
                local tgt_icon = is_running and icons.running or icons.target
                table.insert(items, {
                  idx = idx,
                  text = tgt_icon .. " " .. tgt.name,
                  item_type = "target",
                  project_name = detail.name,
                  target_name = tgt.name,
                  executor = tgt.executor or "",
                  is_running = is_running,
                  parent = project_item,
                  last = is_last_target,
                })
              end

              ::continue::
            end
          end

          -- Determine which groups exist for the last flag
          local has_apps = #apps > 0
          local has_libs = #libs > 0
          add_group("apps", icons.app, apps, not has_libs)
          add_group("libs", icons.lib, libs, true)

          callback(items)
        end
      end)
    end
  end)
end

function M.open()
  local root = workspace.root()
  if not root then
    notify.warn("No Nx workspace detected")
    return
  end

  local ok, snacks = pcall(require, "snacks")
  if not ok then
    notify.error("snacks.nvim is required")
    return
  end

  local icons = config.get().icons
  local cfg = config.get().explorer

  notify.info("Loading projects...")

  build_items(function(items)
    if #items == 0 then
      notify.warn("No projects found")
      return
    end

    state.picker = snacks.picker({
      title = "Nx Explorer",
      items = items,
      focus = "list",  -- start in normal mode navigating the tree
      layout = {
        preset = "sidebar",
        preview = false,
        layout = {
          position = cfg.side,
          width = cfg.width,
          border = "none",
        },
      },
      tree = true,
      formatters = { file = { filename_only = true } },
      format = function(item, picker)
        -- Use Snacks' built-in tree formatter for indentation lines
        local tree_indent = require("snacks.picker.format").tree(item, picker)
        local ret = {}
        vim.list_extend(ret, tree_indent)

        if item.item_type == "group" then
          ret[#ret + 1] = { item.text, "Title" }
        elseif item.item_type == "project" then
          local hl = item.has_running and "DiagnosticOk" or "Function"
          ret[#ret + 1] = { item.text, hl }
        elseif item.item_type == "target" then
          local hl = item.is_running and "DiagnosticOk" or "Special"
          ret[#ret + 1] = { item.text, hl }
        else
          ret[#ret + 1] = { item.text }
        end
        return ret
      end,
      confirm = function(picker, item)
        if not item then return end
        if item.item_type == "target" then
          runner.run(item.project_name, item.target_name)
        elseif item.node_id then
          -- Toggle collapse for groups and projects
          if state.collapsed[item.node_id] then
            state.collapsed[item.node_id] = nil
          else
            state.collapsed[item.node_id] = true
          end
          M._reopen()
        end
      end,
      actions = {
        run_with_args = function(picker, item)
          if not item or item.item_type ~= "target" then return end
          vim.ui.input({ prompt = "Extra args: " }, function(input)
            if input then
              runner.run(item.project_name, item.target_name, input)
            end
          end)
        end,
        goto_root = function(picker, item)
          if not item then return end
          local project_name = item.project_name
          if project_name then
            projects.detail(project_name, function(detail)
              local ws_root = workspace.root()
              if ws_root and detail.root then
                vim.cmd("edit " .. ws_root .. "/" .. detail.root)
              end
            end)
          end
        end,
        open_project_json = function(picker, item)
          if not item then return end
          local project_name = item.project_name
          if project_name then
            projects.detail(project_name, function(detail)
              local ws_root = workspace.root()
              if ws_root and detail.root then
                local pjson = ws_root .. "/" .. detail.root .. "/project.json"
                if vim.fn.filereadable(pjson) == 1 then
                  vim.cmd("edit " .. pjson)
                else
                  notify.warn("No project.json found")
                end
              end
            end)
          end
        end,
        refresh_tree = function(picker)
          projects.reset()
          state.collapsed = nil  -- reset collapse state
          M._reopen()
        end,
        collapse_node = function(picker, item)
          if not item or not item.node_id then return end
          state.collapsed[item.node_id] = true
          M._reopen()
        end,
        expand_node = function(picker, item)
          if not item or not item.node_id then return end
          state.collapsed[item.node_id] = nil
          M._reopen()
        end,
      },
      win = {
        input = {
          keys = {
            ["<C-r>"] = { "run_with_args", mode = { "n", "i" }, desc = "Run with args" },
            ["gd"] = { "goto_root", desc = "Go to project root" },
            ["gp"] = { "open_project_json", desc = "Open project.json" },
            ["r"] = { "refresh_tree", desc = "Refresh" },
          },
        },
        list = {
          keys = {
            ["<C-r>"] = { "run_with_args", desc = "Run with args" },
            ["gd"] = { "goto_root", desc = "Go to project root" },
            ["gp"] = { "open_project_json", desc = "Open project.json" },
            ["r"] = { "refresh_tree", desc = "Refresh" },
            ["h"] = { "collapse_node", desc = "Collapse" },
            ["l"] = { "expand_node", desc = "Expand" },
          },
        },
      },
    })
  end)
end

function M.close()
  if state.picker then
    state.picker:close()
    state.picker = nil
  end
end

function M.toggle()
  if state.picker and not state.picker.closed then
    M.close()
  else
    M.open()
  end
end

--- Close and reopen the sidebar with fresh items (preserves collapse state).
function M._reopen()
  local was_open = state.picker and not state.picker.closed
  if was_open then
    state.picker:close()
    state.picker = nil
  end
  -- Schedule to let the close finish before reopening
  vim.schedule(function()
    M.open()
  end)
end

--- Refresh the sidebar if it's open (called by NxTaskChanged event).
function M.refresh()
  if state.picker and not state.picker.closed then
    M._reopen()
  end
end

return M
