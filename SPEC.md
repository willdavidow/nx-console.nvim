# nx.nvim — Plugin Specification

> A first-class Nx monorepo experience for Neovim, powered by snacks.nvim primitives.

---

## Overview

`nx.nvim` is a Neovim plugin that brings the core workflows of Nx Console into the terminal editor — project browsing, target execution, code generation, and run history — using **snacks.nvim** as the primary UI layer. The goal is not a pixel-perfect VSCode port, but a plugin that feels native to Neovim: keyboard-first, composable, and fast.

**Design philosophy:**
- Every action reachable from the keyboard in ≤ 3 keystrokes
- snacks.nvim for all UI: picker, notifier, terminal, explorer, dashboard integrations
- No UI framework dependencies beyond snacks.nvim + nui.nvim (forms only)
- Lazy data loading — never block the editor
- Works with any Nx workspace version ≥ 14

---

## Snacks.nvim Integration Map

| Feature | Snacks primitive used |
|---|---|
| Project/target picker | `Snacks.picker` (custom source) |
| Generator picker | `Snacks.picker` (custom source) |
| Task output | `Snacks.terminal` (floating or split) |
| Notifications (task start/done/fail) | `Snacks.notifier` |
| Sidebar project explorer | `Snacks.explorer` (custom tree entries) |
| Recent runs | `Snacks.picker` (history source) |
| Dashboard widget | `Snacks.dashboard` (section) |
| Word-at-cursor project lookup | `Snacks.picker` (filter pre-seeded) |

---

## Directory Structure

```
nx.nvim/
├── lua/
│   └── nx/
│       ├── init.lua            -- Public API + setup()
│       ├── config.lua          -- Default config + user merging
│       ├── workspace.lua       -- Nx workspace detection + caching
│       ├── projects.lua        -- Project/target data layer (nx CLI calls)
│       ├── generators.lua      -- Generator schema parser
│       ├── runner.lua          -- Task execution via Snacks.terminal
│       ├── history.lua         -- Persistent run history (JSON on disk)
│       ├── pickers.lua         -- All Snacks.picker custom sources
│       ├── sidebar.lua         -- Snacks.explorer custom integration
│       ├── forms.lua           -- nui.nvim generator forms
│       ├── notify.lua          -- Snacks.notifier wrappers
│       └── utils.lua           -- Shared helpers
├── plugin/
│   └── nx.lua                  -- Autocommands + lazy-load trigger
└── README.md
```

---

## Feature Specifications

---

### 1. Workspace Detection

**Behavior:**
- On `BufEnter`, walk up the directory tree looking for `nx.json`
- Cache the workspace root for the session
- Expose `require("nx").workspace_root()` for other plugins/statuslines
- If no `nx.json` found, all commands no-op with a `Snacks.notifier` warning

**Config:**
```lua
workspace = {
  auto_detect = true,       -- walk up on BufEnter
  cache_ttl = 30,           -- seconds before re-scanning CLI data
}
```

---

### 2. Project + Target Picker

**Trigger:** `<leader>nx` (default, configurable)

**Behavior:**
- Opens `Snacks.picker` with a custom source listing all projects
- Each item shows: project name, type (app/lib), root path
- On selection: opens a **second picker** scoped to that project's targets
- Target items show: target name, executor type
- On target selection: runs the target (see Runner)
- Supports `<C-s>` to run with extra args (prompts for additional CLI flags)

**Preview pane:**
- Shows `project.json` content for the selected project
- Updates live as you navigate

**Picker item format:**
```
[app]  my-app                 apps/my-app
[lib]  ui-components          libs/ui/components
[lib]  data-access-users      libs/data-access/users
```

---

### 3. Sidebar — Project Explorer

**Trigger:** `<leader>ne` or `:NxExplorer`

**Behavior:**
- Integrates with `Snacks.explorer` as a custom tree source
- Shows workspace project tree grouped by type (apps / libs) and optionally by tags
- Each project node is expandable to show its targets
- Selecting a target runs it immediately (or opens run dialog if configured)
- Right-side panel or left-side panel (configurable)
- Width configurable (default 40 cols)

**Tree structure:**
```
 NX WORKSPACE
 ├──  apps
 │    ├──  my-app
 │    │    ├── ▶ build
 │    │    ├── ▶ serve
 │    │    ├── ▶ test
 │    │    └── ▶ lint
 │    └──  my-app-e2e
 │         └── ▶ e2e
 └──  libs
      ├──  ui-components
      │    ├── ▶ build
      │    └── ▶ test
      └──  data-access-users
           ├── ▶ build
           └── ▶ test
```

**Keymaps inside explorer:**
| Key | Action |
|---|---|
| `<CR>` | Run target / expand project |
| `<C-r>` | Run with extra args |
| `gd` | Go to project root directory |
| `gp` | Open `project.json` in buffer |
| `r` | Refresh workspace data |

---

### 4. Task Runner

**Behavior:**
- Executes `nx run <project>:<target> [args]` via `Snacks.terminal`
- Terminal opens in a **floating window** by default (configurable: float, hsplit, vsplit)
- Each run gets a unique terminal instance (doesn't reuse/stomp previous runs)
- On task completion: fires `Snacks.notifier` with success/failure + duration
- Exit code tracked for history

**Terminal config defaults:**
```lua
runner = {
  terminal_style = "float",   -- "float" | "split" | "vsplit"
  float_width = 0.8,
  float_height = 0.7,
  auto_close_on_success = false,
  notify_on_complete = true,
}
```

**Floating terminal header shows:**
```
 nx run my-app:build  ●  running...
```
Updates to:
```
 nx run my-app:build  ✓  completed in 12.4s
```

---

### 5. Generator Picker + Form

**Trigger:** `<leader>ng` or `:NxGenerate`

**Phase 1 — Collection picker:**
- `Snacks.picker` listing all available generator collections (e.g., `@nx/react`, `@nx/node`)
- Preview pane shows collection description

**Phase 2 — Generator picker:**
- After selecting collection, second picker lists generators in that collection
- Preview shows generator description + required options summary

**Phase 3 — Form (nui.nvim):**
- Parses the generator's JSON schema
- Renders a floating form with fields:

| Schema type | Form widget |
|---|---|
| `string` | Text input |
| `boolean` | Toggle (`y`/`n`) |
| `enum` | Inline select list |
| `array` | Multi-entry text input |
| `number` | Number input with validation |

- Required fields marked with `*`
- Defaults pre-filled
- Description shown below each field
- `<Tab>` / `<S-Tab>` to navigate fields
- `<CR>` on last field or `<C-s>` anywhere to submit
- Submission builds and executes: `nx generate <collection>:<generator> --field=value ...`
- Output opens in `Snacks.terminal`

---

### 6. Run History

**Behavior:**
- Persists run history to `~/.local/share/nvim/nx-history.json`
- Stores: command, project, target, args, exit code, duration, timestamp
- Accessible via `<leader>nh` or `:NxHistory`

**Picker view:**
```
✓  my-app:build           12.4s   2 min ago
✓  ui-components:test     8.1s    1 hr ago
✗  my-app:test            3.2s    1 hr ago   (failed)
▶  data-access:lint       --      running
```

**Actions in history picker:**
| Key | Action |
|---|---|
| `<CR>` | Re-run the selected command |
| `<C-y>` | Yank the full nx command to clipboard |
| `<C-d>` | Delete entry from history |
| `<C-o>` | Open the terminal output (if still alive) |

---

### 7. Affected Picker

**Trigger:** `<leader>na` or `:NxAffected`

**Behavior:**
- Runs `nx show projects --affected` against current branch (or configurable base)
- Opens `Snacks.picker` with only affected projects
- Same UX as project picker — select project → select target → run
- Useful for CI-style "only run what changed" workflows

**Config:**
```lua
affected = {
  base = "main",    -- git base branch for affected calculation
}
```

---

### 8. Current File Context

**Trigger:** `<leader>nf` or `:NxCurrentProject`

**Behavior:**
- Detects which Nx project the current buffer belongs to (by matching file path against project roots)
- Opens target picker **pre-filtered** to that project
- If no match: notifies "File not in any Nx project"

This is the highest-frequency workflow: you're editing a file and want to run its tests/build without navigating.

---

### 9. Statusline / Winbar Integration

**Exposes:**
```lua
require("nx").current_project()   -- returns project name for current buffer, or nil
require("nx").running_tasks()     -- returns count of currently running tasks
```

Compatible with lualine, heirline, incline, etc. Example lualine component:

```lua
{
  function()
    local p = require("nx").current_project()
    return p and ("󱄅 " .. p) or ""
  end,
  color = { fg = "#7aa2f7" }
}
```

---

### 10. Dashboard Integration

If `Snacks.dashboard` is configured, `nx.nvim` can inject a section:

```lua
-- In your snacks dashboard config:
{ section = "nx_recent", title = "Recent NX Runs", limit = 5 }
```

Shows last 5 runs with status icons. Selecting one re-runs it.

---

## Default Keymap Reference

All keymaps use `<leader>n` as the namespace and are fully remappable.

| Keymap | Command | Description |
|---|---|---|
| `<leader>nx` | `:NxProjects` | Project + target picker |
| `<leader>ne` | `:NxExplorer` | Toggle sidebar explorer |
| `<leader>ng` | `:NxGenerate` | Generator picker + form |
| `<leader>nh` | `:NxHistory` | Run history picker |
| `<leader>na` | `:NxAffected` | Affected projects picker |
| `<leader>nf` | `:NxCurrentProject` | Current file's project targets |
| `<leader>nr` | `:NxRerun` | Re-run last command |
| `<leader>ns` | `:NxStop` | Stop running task(s) |
| `<leader>nR` | `:NxRefresh` | Refresh workspace cache |

**Which-key group registration** (auto-registered if which-key is present):
```lua
{ "<leader>n", group = "Nx" }
```

---

## Configuration Reference

Full default config with all options:

```lua
require("nx").setup({
  -- Workspace
  workspace = {
    auto_detect = true,
    cache_ttl = 30,
  },

  -- Runner
  runner = {
    terminal_style = "float",   -- "float" | "split" | "vsplit"
    float_width = 0.8,
    float_height = 0.7,
    auto_close_on_success = false,
    notify_on_complete = true,
  },

  -- Sidebar
  explorer = {
    side = "left",              -- "left" | "right"
    width = 40,
    group_by = "type",          -- "type" | "tags" | "flat"
    auto_open = false,          -- open on startup if nx.json found
  },

  -- Generator forms
  generators = {
    skip_optional = false,      -- skip optional fields, use defaults
    confirm_before_run = true,  -- show assembled command before executing
  },

  -- Affected
  affected = {
    base = "main",
  },

  -- History
  history = {
    max_entries = 100,
    persist = true,
  },

  -- Keymaps (set any to false to disable)
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
  },

  -- Icons (override with your nerd font preference)
  icons = {
    app        = "",
    lib        = "󰏗",
    target     = "▶",
    running    = "●",
    success    = "✓",
    failure    = "✗",
    nx         = "󱄅",
  },
})
```

---

## Dependencies

| Dependency | Required | Purpose |
|---|---|---|
| `folke/snacks.nvim` | **Required** | Picker, terminal, notifier, explorer |
| `MunifTanjim/nui.nvim` | **Required** | Generator forms |
| `nvim-lua/plenary.nvim` | **Required** | Async jobs, path utils |
| `folke/which-key.nvim` | Optional | Keymap group labels |
| Nx CLI (`nx` or `npx nx`) | **Required** | Data source for all features |

---

## Data Layer — Nx CLI Commands Used

```bash
# Workspace detection
cat nx.json

# All projects
nx show projects --json

# Single project detail
nx show project <name> --json

# Affected projects
nx show projects --affected --base=main --json

# Generator list
nx list --json
nx list <collection> --json

# Generator schema
nx generate <collection>:<generator> --help --json

# Run target
nx run <project>:<target> [--extra=args]

# Graph (delegated to browser)
nx graph
```

---

## Out of Scope (Intentionally)

- **Project graph visualization** — delegate to `nx graph` (opens browser). A `:NxGraph` command will run it.
- **Nx Cloud integration** — out of scope for v1
- **Non-Nx monorepos** — Nx workspaces only (no Turborepo, Lerna, etc.)
- **Windows support** — v1 targets macOS/Linux only

---

## Implementation Phases

### Phase 1 — Foundation (Day 1)
- [ ] Plugin scaffold + `setup()` + config merging
- [ ] Workspace detection + caching
- [ ] `projects.lua` data layer (async CLI calls via plenary)
- [ ] Basic project + target picker (`Snacks.picker`)
- [ ] Task runner via `Snacks.terminal`
- [ ] Notifications via `Snacks.notifier`

### Phase 2 — Sidebar + History (Day 2)
- [ ] `Snacks.explorer` sidebar integration
- [ ] Run history (persist + picker)
- [ ] Current file context detection (`<leader>nf`)
- [ ] Affected projects picker
- [ ] Statusline integration

### Phase 3 — Generators (Day 3-4)
- [ ] Collection + generator pickers
- [ ] JSON schema parser
- [ ] nui.nvim form renderer
- [ ] All field types: string, boolean, enum, array, number
- [ ] Confirm-before-run dialog

### Phase 4 — Polish (Day 4-5)
- [ ] which-key registration
- [ ] Dashboard section
- [ ] `:NxGraph` browser delegate
- [ ] Rerun last / stop running tasks
- [ ] Edge cases: missing nx CLI, corrupt workspace, empty projects
- [ ] README + docs

---

## Open Questions for Implementation

1. **Explorer approach**: Custom `Snacks.explorer` tree source vs. a standalone `nui.nvim` tree panel? snacks explorer integration is newer and may have limitations — worth prototyping both.
2. **Async strategy**: plenary async vs. `vim.system()` (Neovim 0.10+)? `vim.system` is cleaner but limits Neovim version support.
3. **Form UX**: Single scrollable form vs. wizard-style step-through for generators with many fields?
4. **Terminal reuse**: Should re-running the same target reuse the terminal buffer or always spawn fresh?
