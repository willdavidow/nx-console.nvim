local config = require("nx.config")

local M = {}

function M.format_items(entries, limit)
  local icons = config.get().icons
  local history = require("nx.history")
  local items = {}

  for i, entry in ipairs(entries) do
    if i > limit then break end
    local status_icon = entry.exit_code == 0 and icons.success or icons.failure
    local label = entry.project .. ":" .. entry.target
    local duration = entry.duration and string.format("%.1fs", entry.duration) or "--"
    local time_ago = history.format_relative_time(entry.timestamp)

    table.insert(items, {
      icon = status_icon,
      label = label .. "  " .. duration .. "  " .. time_ago,
      action = function()
        require("nx.runner").run(entry.project, entry.target, entry.args)
      end,
      project = entry.project,
      target = entry.target,
    })
  end

  return items
end

function M.register()
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.dashboard then return end

  snacks.dashboard.sections.nx_recent = function(section)
    local history = require("nx.history")
    local entries = history.list()
    local limit = section.limit or 5
    local items = M.format_items(entries, limit)

    if #items == 0 then
      return { { text = "  No recent runs", hl = "Comment" } }
    end

    local result = {}
    for _, item in ipairs(items) do
      table.insert(result, {
        text = "  " .. item.icon .. " " .. item.label,
        action = item.action,
        hl = "Normal",
      })
    end
    return result
  end
end

return M
