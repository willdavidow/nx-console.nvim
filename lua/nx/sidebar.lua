local config = require("nx.config")
local projects = require("nx.projects")
local workspace = require("nx.workspace")
local runner = require("nx.runner")
local notify = require("nx.notify")

local M = {}

local state = {
  picker = nil,
}

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

          local icons = config.get().icons
          local items = {}
          local idx = 0

          local function add_group(group_name, group_icon, group_projects)
            if #group_projects == 0 then return end
            idx = idx + 1
            local group_item = {
              idx = idx,
              text = group_icon .. " " .. group_name,
              item_type = "group",
              group_name = group_name,
            }
            table.insert(items, group_item)

            for _, detail in ipairs(group_projects) do
              idx = idx + 1
              local has_running = false
              for _, tgt in ipairs(detail.targets) do
                if runner.is_running(detail.name, tgt.name) then
                  has_running = true
                  break
                end
              end

              local pi = detail.type == "application" and icons.app or icons.lib
              local project_text = pi .. " " .. detail.name
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
                parent = group_item,
              }
              table.insert(items, project_item)

              for _, tgt in ipairs(detail.targets) do
                idx = idx + 1
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
                })
              end
            end
          end

          add_group("apps", icons.app, apps)
          add_group("libs", icons.lib, libs)

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
        local ret = { { item.text } }
        if item.item_type == "group" then
          ret = { { item.text, "Title" } }
        elseif item.item_type == "project" then
          local hl = item.has_running and "DiagnosticOk" or "Function"
          ret = { { item.text, hl } }
        elseif item.item_type == "target" then
          local hl = item.is_running and "DiagnosticOk" or "Special"
          ret = { { item.text, hl } }
        end
        return ret
      end,
      confirm = function(picker, item)
        if not item then return end
        if item.item_type == "target" then
          runner.run(item.project_name, item.target_name)
        elseif item.item_type == "project" then
          -- Toggle expand in tree
          picker:action("toggle")
        elseif item.item_type == "group" then
          picker:action("toggle")
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
          build_items(function(new_items)
            picker:set_items(new_items)
          end)
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

--- Refresh the sidebar if it's open (called by NxTaskChanged event).
function M.refresh()
  if state.picker and not state.picker.closed then
    build_items(function(new_items)
      if state.picker and not state.picker.closed then
        state.picker:set_items(new_items)
      end
    end)
  end
end

return M
