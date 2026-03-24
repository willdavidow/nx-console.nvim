# nx.nvim

A first-class Nx monorepo experience for Neovim, powered by [snacks.nvim](https://github.com/folke/snacks.nvim) and [nui.nvim](https://github.com/MunifTanjim/nui.nvim).

## Features

- **Project + Target Picker** — Browse all projects, select targets, run them
- **Sidebar Explorer** — nui.nvim tree panel showing projects grouped by type with running task indicators
- **Task Panel** — Persistent bottom split for long-running processes (servers, watchers) with buffer switching
- **Generator Forms** — Interactive nui.nvim forms for `nx generate` with all field types
- **Run History** — Persistent history with rerun, yank, and delete
- **Affected Projects** — Picker scoped to `nx show projects --affected`
- **Current File Context** — Instantly run targets for the project your current file belongs to
- **Statusline Integration** — `current_project()` and `running_tasks()` for lualine/heirline
- **Dashboard** — Snacks.dashboard section showing recent runs
- **Smart Terminal Routing** — Long-running targets (serve, dev, storybook) auto-route to the task panel; short-lived tasks use floating terminals

## Requirements

- Neovim ≥ 0.10
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) — picker, terminal, notifier, dashboard
- [MunifTanjim/nui.nvim](https://github.com/MunifTanjim/nui.nvim) — sidebar explorer, generator forms
- Nx CLI (`nx` or `npx nx`) — data source for all features

## Installation

### lazy.nvim

```lua
{
  "willdavidow/nx-console.nvim",
  dependencies = {
    "folke/snacks.nvim",
    "MunifTanjim/nui.nvim",
  },
  opts = {},
  cmd = {
    "NxProjects", "NxExplorer", "NxGenerate", "NxHistory",
    "NxAffected", "NxCurrentProject", "NxRerun", "NxStop",
    "NxRefresh", "NxPanel", "NxGraph",
  },
  keys = {
    { "<leader>nx", "<cmd>NxProjects<cr>", desc = "Nx: projects" },
    { "<leader>ne", "<cmd>NxExplorer<cr>", desc = "Nx: explorer" },
    { "<leader>ng", "<cmd>NxGenerate<cr>", desc = "Nx: generate" },
    { "<leader>nh", "<cmd>NxHistory<cr>", desc = "Nx: history" },
    { "<leader>na", "<cmd>NxAffected<cr>", desc = "Nx: affected" },
    { "<leader>nf", "<cmd>NxCurrentProject<cr>", desc = "Nx: current file" },
    { "<leader>nr", "<cmd>NxRerun<cr>", desc = "Nx: rerun last" },
    { "<leader>ns", "<cmd>NxStop<cr>", desc = "Nx: stop tasks" },
    { "<leader>nR", "<cmd>NxRefresh<cr>", desc = "Nx: refresh" },
    { "<leader>np", "<cmd>NxPanel<cr>", desc = "Nx: panel" },
  },
}
```

## Commands

| Command | Description |
|---|---|
| `:NxProjects` | Project + target picker |
| `:NxExplorer` | Toggle sidebar explorer |
| `:NxGenerate` | Generator picker + form |
| `:NxHistory` | Run history picker |
| `:NxAffected` | Affected projects picker |
| `:NxCurrentProject` | Current file's project targets |
| `:NxRerun` | Re-run last command |
| `:NxStop` | Stop running task(s) |
| `:NxRefresh` | Refresh workspace cache |
| `:NxPanel` | Toggle task panel |
| `:NxPanelPick` | Pick task in panel |
| `:NxGraph` | Open project graph in browser |

## Default Keymaps

All keymaps use `<leader>n` as the namespace and are fully remappable via config.

| Keymap | Command |
|---|---|
| `<leader>nx` | `:NxProjects` |
| `<leader>ne` | `:NxExplorer` |
| `<leader>ng` | `:NxGenerate` |
| `<leader>nh` | `:NxHistory` |
| `<leader>na` | `:NxAffected` |
| `<leader>nf` | `:NxCurrentProject` |
| `<leader>nr` | `:NxRerun` |
| `<leader>ns` | `:NxStop` |
| `<leader>nR` | `:NxRefresh` |
| `<leader>np` | `:NxPanel` |

## Task Panel

Long-running tasks (`serve`, `dev`, `start`, `watch`, `storybook`, and any target containing these substrings) automatically open in a persistent bottom split instead of a floating terminal.

**Panel keymaps (inside the panel):**

| Key | Action |
|---|---|
| `]t` | Next task buffer |
| `[t` | Previous task buffer |
| `<C-c>` | Kill the active process |
| `q` | Hide panel (processes keep running) |

The panel shows a statusline with the active task name and buffer count (e.g. `󱄅 my-app:serve [1/3] ●`). Toggle with `<leader>np` or `:NxPanel`. Pick a specific task with `:NxPanelPick`.

## Sidebar Explorer

**Keymaps (inside the explorer):**

| Key | Action |
|---|---|
| `<CR>` | Run target / expand-collapse project |
| `<C-r>` | Run target with extra args |
| `gd` | Go to project root directory |
| `gp` | Open `project.json` |
| `r` | Refresh workspace data |
| `q` | Close sidebar |

Running targets show a `●` indicator with green highlighting. The sidebar auto-refreshes when tasks start or stop — no need to manually refresh.

## Statusline Integration

```lua
-- lualine example
{
  function()
    local p = require("nx").current_project()
    return p and ("󱄅 " .. p) or ""
  end,
  color = { fg = "#7aa2f7" },
}
```

Available functions:
- `require("nx").current_project()` — project name for current buffer
- `require("nx").running_tasks()` — count of running tasks
- `require("nx").workspace_root()` — workspace root path

## Dashboard Integration

Add to your Snacks.dashboard config:

```lua
{ section = "nx_recent", title = "Recent NX Runs", limit = 5 }
```

## Configuration

```lua
require("nx").setup({
  workspace = {
    auto_detect = true,
    cache_ttl = 30,
  },
  runner = {
    terminal_style = "float",
    float_width = 0.8,
    float_height = 0.7,
    auto_close_on_success = false,
    notify_on_complete = true,
    long_running_targets = { "serve", "dev", "start", "watch", "storybook" },
  },
  panel = {
    position = "bottom",
    height = 15,
    width = 80,
    auto_show = true,
  },
  explorer = {
    side = "left",
    width = 40,
    group_by = "type",
    auto_open = false,
  },
  generators = {
    skip_optional = false,
    confirm_before_run = true,
  },
  affected = {
    base = "main",
  },
  history = {
    max_entries = 100,
    persist = true,
  },
  keys = {
    projects   = "<leader>nx",
    explorer   = "<leader>ne",
    generate   = "<leader>ng",
    history    = "<leader>nh",
    affected   = "<leader>na",
    current    = "<leader>nf",
    rerun      = "<leader>nr",
    stop       = "<leader>ns",
    refresh    = "<leader>nR",
    panel      = "<leader>np",
  },
})
```

All keys can be set to `false` to disable that keymap.

## License

MIT
