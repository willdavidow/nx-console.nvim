local projects = require("nx.projects")
local config = require("nx.config")
local runner = require("nx.runner")
local workspace = require("nx.workspace")
local notify = require("nx.notify")

local M = {}

--- Open the target picker for a given project.
--- @param project_name string
function M.targets(project_name)
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    notify.error("snacks.nvim is required")
    return
  end

  projects.detail(project_name, function(detail)
    if #detail.targets == 0 then
      notify.warn("No targets found for " .. project_name)
      return
    end

    local icons = config.get().icons
    local items = {}
    for _, tgt in ipairs(detail.targets) do
      table.insert(items, {
        text = tgt.name .. " " .. tgt.executor,
        target = tgt,
        preview = {
          text = "Executor: " .. tgt.executor .. "\n\nRun: nx run " .. project_name .. ":" .. tgt.name,
        },
      })
    end

    snacks.picker({
      title = icons.nx .. " " .. project_name .. " targets",
      items = items,
      format = function(item, picker)
        return {
          { icons.target .. " ", "Special" },
          { item.target.name, "Function" },
          { "  " },
          { item.target.executor, "Comment" },
        }
      end,
      confirm = function(picker, item)
        picker:close()
        runner.run(project_name, item.target.name)
      end,
      actions = {
        run_with_args = function(picker, item)
          picker:close()
          vim.ui.input({ prompt = "Extra args: " }, function(input)
            if input then
              runner.run(project_name, item.target.name, input)
            end
          end)
        end,
      },
      win = {
        input = {
          keys = {
            ["<C-s>"] = { "run_with_args", mode = { "n", "i" }, desc = "Run with extra args" },
          },
        },
      },
    })
  end)
end

--- Render project detail into the preview pane.
local function render_project_preview(ctx, detail, icons)
  ctx.preview:reset()
  local root_dir = workspace.root()
  local project_json = root_dir .. "/" .. detail.root .. "/project.json"
  if vim.fn.filereadable(project_json) == 1 then
    ctx.preview:set_buf(vim.fn.bufadd(project_json))
  else
    local lines = {
      "Project: " .. detail.name,
      "Root: " .. detail.root,
      "Type: " .. detail.type,
      "",
      "Targets:",
    }
    for _, tgt in ipairs(detail.targets) do
      table.insert(lines, "  " .. icons.target .. " " .. tgt.name .. "  (" .. tgt.executor .. ")")
    end
    ctx.preview:set_lines(lines)
  end
end

--- Open the project picker.
--- Shows project names immediately; fetches detail on demand for preview.
function M.projects()
  local root = workspace.root()
  if not root then
    notify.warn("No Nx workspace detected. Open a file inside an Nx workspace.")
    return
  end

  local ok, snacks = pcall(require, "snacks")
  if not ok then
    notify.error("snacks.nvim is required")
    return
  end

  local icons = config.get().icons

  projects.list(function(names)
    if #names == 0 then
      notify.warn("No projects found")
      return
    end

    -- Build items from names only — no N+1 detail fetches upfront
    local items = {}
    for _, name in ipairs(names) do
      table.insert(items, {
        text = name,
        project_name = name,
      })
    end
    table.sort(items, function(a, b) return a.text < b.text end)

    snacks.picker({
      title = icons.nx .. " Nx Projects",
      items = items,
      format = function(item, picker)
        local detail = item._detail
        if detail then
          local tl = detail.type == "application" and "app" or "lib"
          local ti = detail.type == "application" and icons.app or icons.lib
          return {
            { ti .. " [" .. tl .. "]", detail.type == "application" and "Keyword" or "Type" },
            { "  " },
            { detail.name, "Function" },
            { "  " },
            { detail.root, "Comment" },
          }
        end
        -- Before detail is loaded, show name only
        return {
          { icons.lib .. " ", "Type" },
          { item.project_name, "Function" },
        }
      end,
      preview = function(ctx)
        local item = ctx.item
        -- Fetch detail lazily on preview
        if not item._detail then
          projects.detail(item.project_name, function(detail)
            item._detail = detail
            if ctx.preview then
              render_project_preview(ctx, detail, icons)
            end
          end)
          -- Show loading text while fetching
          ctx.preview:set_lines({ "Loading project details..." })
          return
        end

        render_project_preview(ctx, item._detail, icons)
      end,
      confirm = function(picker, item)
        picker:close()
        M.targets(item.project_name)
      end,
    })
  end)
end

--- Open target picker for the current file's project.
function M.current_file()
  local nx = require("nx")
  nx.current_project(function(project)
    if project then
      M.targets(project)
    else
      notify.warn("Current file is not in any Nx project")
    end
  end)
end

--- Open picker showing only affected projects.
function M.affected()
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

  local cfg = config.get()
  local icons = cfg.icons
  local base = cfg.affected.base

  local utils = require("nx.utils")
  local cmd = workspace.nx_cmd({ "show", "projects", "--affected", "--base=" .. base, "--json" })

  utils.exec(cmd, function(stdout)
    local names = require("nx.projects").parse_project_list(stdout)
    if #names == 0 then
      notify.info("No affected projects")
      return
    end

    local items = {}
    for _, name in ipairs(names) do
      table.insert(items, {
        text = name,
        project_name = name,
      })
    end
    table.sort(items, function(a, b) return a.text < b.text end)

    snacks.picker({
      title = icons.nx .. " Affected Projects (base: " .. base .. ")",
      items = items,
      format = function(item, picker)
        return {
          { icons.lib .. " ", "Type" },
          { item.project_name, "Function" },
        }
      end,
      confirm = function(picker, item)
        picker:close()
        M.targets(item.project_name)
      end,
    })
  end, function(err)
    notify.error("Failed to get affected projects: " .. (err or "unknown"))
  end)
end

return M
