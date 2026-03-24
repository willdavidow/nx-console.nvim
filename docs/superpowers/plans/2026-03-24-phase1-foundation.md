# Phase 1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the core data layer and UI for nx.nvim — workspace detection, project/target data, picker, task runner, and notifications.

**Architecture:** Plugin scaffold with `setup()` entry point, config merging via `vim.tbl_deep_extend`. Workspace detection walks up directory tree for `nx.json`, caches result per session. All Nx CLI calls use `vim.system()` async with callbacks. UI layer uses `Snacks.picker` for project/target selection, `Snacks.terminal` for task execution, `Snacks.notifier` for status updates.

**Tech Stack:** Neovim 0.10+ (`vim.system()`), snacks.nvim (picker, terminal, notifier), Lua 5.1

**Note on dependencies:** The spec lists plenary.nvim as required, but since we're using `vim.system()` for async and `vim.fs` for path utilities, plenary is **not needed in Phase 1**. It may be added later if needed for testing or other utilities.

---

## File Structure

| File | Responsibility |
|---|---|
| `lua/nx/config.lua` | Default config table, `config.setup(user_opts)` merges user overrides |
| `lua/nx/workspace.lua` | Find `nx.json` by walking up from cwd, cache root path, detect nx binary |
| `lua/nx/utils.lua` | Shared helpers: async CLI runner wrapper around `vim.system()` |
| `lua/nx/notify.lua` | Thin wrappers around `Snacks.notifier` with nx-prefixed titles |
| `lua/nx/projects.lua` | Fetch project list and project detail via `nx show` commands |
| `lua/nx/runner.lua` | Execute `nx run project:target` via `Snacks.terminal`, track exit codes |
| `lua/nx/pickers.lua` | `Snacks.picker` custom sources for project list and target list |
| `lua/nx/init.lua` | Public API: `setup()`, `workspace_root()`, user commands, keymaps |
| `plugin/nx.lua` | Autocommands: `BufEnter` workspace detection, lazy-load trigger |
| `tests/nx/config_spec.lua` | Tests for config merging |
| `tests/nx/workspace_spec.lua` | Tests for workspace detection logic |
| `tests/nx/projects_spec.lua` | Tests for project data parsing |
| `tests/minimal_init.lua` | Minimal nvim config for running tests headless |

---

## Task 1: Plugin scaffold — config + setup

**Files:**
- Create: `lua/nx/config.lua`
- Create: `lua/nx/init.lua` (partial — setup only)
- Create: `tests/minimal_init.lua`
- Create: `tests/nx/config_spec.lua`

- [ ] **Step 1: Create test harness**

Create `tests/minimal_init.lua` — a minimal nvim config that adds the plugin to the runtime path so tests can `require("nx")`.

```lua
-- tests/minimal_init.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.swapfile = false
vim.opt.backup = false
```

- [ ] **Step 2: Write failing test for config defaults**

```lua
-- tests/nx/config_spec.lua
local config = require("nx.config")

describe("nx.config", function()
  before_each(function()
    config.reset()
  end)

  it("returns default config when no user opts provided", function()
    config.setup({})
    local c = config.get()
    assert.is_true(c.workspace.auto_detect)
    assert.equals(30, c.workspace.cache_ttl)
    assert.equals("float", c.runner.terminal_style)
    assert.equals(0.8, c.runner.float_width)
    assert.equals(100, c.history.max_entries)
  end)

  it("merges user overrides with defaults", function()
    config.setup({ workspace = { cache_ttl = 60 }, runner = { terminal_style = "split" } })
    local c = config.get()
    assert.is_true(c.workspace.auto_detect) -- untouched default
    assert.equals(60, c.workspace.cache_ttl) -- overridden
    assert.equals("split", c.runner.terminal_style) -- overridden
    assert.equals(0.7, c.runner.float_height) -- untouched default
  end)

  it("does not mutate defaults on repeated setup calls", function()
    config.setup({ workspace = { cache_ttl = 99 } })
    config.reset()
    config.setup({})
    assert.equals(30, config.get().workspace.cache_ttl)
  end)
end)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/nx/ {minimal_init = 'tests/minimal_init.lua'}" +qa`

Since we don't have plenary yet and this is Phase 1, we'll use a simpler test runner:

Run: `nvim --headless -u tests/minimal_init.lua -l tests/nx/config_spec.lua`

Expected: FAIL — module `nx.config` not found.

**Alternative:** Use `lua` assertions directly (no plenary.busted) for Phase 1. We'll use a minimal `describe`/`it`/`assert` shim.

Create `tests/test_helper.lua`:

```lua
-- tests/test_helper.lua
-- Minimal test shim for running tests in nvim headless mode
local M = {}
local failures = {}
local current_describe = ""

function M.describe(name, fn)
  current_describe = name
  fn()
end

function M.it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("  ✓ " .. current_describe .. " > " .. name)
  else
    print("  ✗ " .. current_describe .. " > " .. name)
    print("    " .. tostring(err))
    table.insert(failures, current_describe .. " > " .. name .. ": " .. tostring(err))
  end
end

function M.assert_eq(expected, actual, msg)
  if expected ~= actual then
    error((msg or "") .. " expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual), 2)
  end
end

function M.assert_true(val, msg)
  if not val then
    error((msg or "") .. " expected truthy, got " .. vim.inspect(val), 2)
  end
end

function M.done()
  if #failures > 0 then
    print("\n" .. #failures .. " FAILED")
    vim.cmd("cq 1")
  else
    print("\nAll passed")
    vim.cmd("qa!")
  end
end

return M
```

Update `tests/nx/config_spec.lua` to use this shim:

```lua
-- tests/nx/config_spec.lua
local t = require("tests.test_helper")
local config = require("nx.config")

t.describe("config defaults", function()
  config.reset()
  config.setup({})
  local c = config.get()

  t.it("has auto_detect true by default", function()
    t.assert_true(c.workspace.auto_detect)
  end)

  t.it("has cache_ttl 30 by default", function()
    t.assert_eq(30, c.workspace.cache_ttl)
  end)

  t.it("has terminal_style float by default", function()
    t.assert_eq("float", c.runner.terminal_style)
  end)
end)

t.describe("config merging", function()
  config.reset()
  config.setup({ workspace = { cache_ttl = 60 }, runner = { terminal_style = "split" } })
  local c = config.get()

  t.it("preserves untouched defaults", function()
    t.assert_true(c.workspace.auto_detect)
    t.assert_eq(0.7, c.runner.float_height)
  end)

  t.it("applies user overrides", function()
    t.assert_eq(60, c.workspace.cache_ttl)
    t.assert_eq("split", c.runner.terminal_style)
  end)
end)

t.describe("config reset isolation", function()
  config.reset()
  config.setup({ workspace = { cache_ttl = 99 } })
  config.reset()
  config.setup({})

  t.it("does not leak state between reset calls", function()
    t.assert_eq(30, config.get().workspace.cache_ttl)
  end)
end)

t.done()
```

- [ ] **Step 4: Implement config.lua**

```lua
-- lua/nx/config.lua
local M = {}

local defaults = {
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
    projects = "<leader>nx",
    explorer = "<leader>ne",
    generate = "<leader>ng",
    history = "<leader>nh",
    affected = "<leader>na",
    current = "<leader>nf",
    rerun = "<leader>nr",
    stop = "<leader>ns",
    refresh = "<leader>nR",
  },
  icons = {
    app = "",
    lib = "󰏗",
    target = "▶",
    running = "●",
    success = "✓",
    failure = "✗",
    nx = "󱄅",
  },
}

local current = nil

function M.setup(user_opts)
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
end

function M.get()
  return current or defaults
end

function M.reset()
  current = nil
end

return M
```

- [ ] **Step 5: Run tests — verify they pass**

Run: `nvim --headless -u tests/minimal_init.lua -l tests/nx/config_spec.lua`
Expected: All passed

- [ ] **Step 6: Stub init.lua with setup()**

```lua
-- lua/nx/init.lua
local M = {}
local config = require("nx.config")

function M.setup(opts)
  config.setup(opts)
end

return M
```

- [ ] **Step 7: Commit**

```bash
git add lua/nx/config.lua lua/nx/init.lua tests/
git commit -m "feat: plugin scaffold with config module and setup()"
```

---

## Task 2: Utility layer — async CLI wrapper

**Files:**
- Create: `lua/nx/utils.lua`
- Create: `tests/nx/utils_spec.lua`

- [ ] **Step 1: Write failing test for exec**

```lua
-- tests/nx/utils_spec.lua
local t = require("tests.test_helper")
local utils = require("nx.utils")

t.describe("utils.exec", function()
  t.it("runs a command and returns stdout via callback", function()
    local done = false
    local result = nil
    utils.exec({ "echo", "hello" }, function(out)
      result = out
      done = true
    end)
    -- vim.system is async, so we need to wait
    vim.wait(2000, function() return done end)
    t.assert_eq("hello\n", result)
  end)

  t.it("calls on_error callback on non-zero exit", function()
    local done = false
    local err_msg = nil
    utils.exec({ "sh", "-c", "exit 1" }, function() end, function(err)
      err_msg = err
      done = true
    end)
    vim.wait(2000, function() return done end)
    t.assert_true(err_msg ~= nil, "expected error callback to fire")
  end)
end)

t.describe("utils.find_up", function()
  t.it("finds a file by walking up directories", function()
    -- Create a temp structure: /tmp/nx-test/sub/deep/ with nx.json at root
    local root = vim.fn.tempname() .. "/nx-test"
    local deep = root .. "/sub/deep"
    vim.fn.mkdir(deep, "p")
    local f = io.open(root .. "/nx.json", "w")
    f:write("{}")
    f:close()

    local found = utils.find_up("nx.json", deep)
    t.assert_eq(root, found)

    -- cleanup
    vim.fn.delete(root, "rf")
  end)

  t.it("returns nil when file not found", function()
    local found = utils.find_up("nx.json", "/tmp")
    t.assert_eq(nil, found)
  end)
end)

t.done()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `nvim --headless -u tests/minimal_init.lua -l tests/nx/utils_spec.lua`
Expected: FAIL — module `nx.utils` not found

- [ ] **Step 3: Implement utils.lua**

```lua
-- lua/nx/utils.lua
local M = {}

--- Run a command asynchronously using vim.system().
--- @param cmd string[] command and args
--- @param on_success fun(stdout: string) called with stdout on exit code 0
--- @param on_error? fun(err: string) called with stderr on non-zero exit
function M.exec(cmd, on_success, on_error)
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        on_success(result.stdout)
      elseif on_error then
        on_error(result.stderr or ("command failed with exit code " .. result.code))
      end
    end)
  end)
end

--- Walk up from `start_dir` looking for `filename`.
--- Returns the directory containing the file, or nil.
--- @param filename string
--- @param start_dir string
--- @return string|nil
function M.find_up(filename, start_dir)
  local found = vim.fs.find(filename, {
    path = start_dir,
    upward = true,
    type = "file",
    limit = 1,
  })
  if found and found[1] then
    return vim.fn.fnamemodify(found[1], ":h")
  end
  return nil
end

return M
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `nvim --headless -u tests/minimal_init.lua -l tests/nx/utils_spec.lua`
Expected: All passed

- [ ] **Step 5: Commit**

```bash
git add lua/nx/utils.lua tests/nx/utils_spec.lua
git commit -m "feat: utils module with async exec and find_up"
```

---

## Task 3: Workspace detection + caching

**Files:**
- Create: `lua/nx/workspace.lua`
- Create: `tests/nx/workspace_spec.lua`

- [ ] **Step 1: Write failing test**

```lua
-- tests/nx/workspace_spec.lua
local t = require("tests.test_helper")
local workspace = require("nx.workspace")

t.describe("workspace.detect", function()
  t.it("finds workspace root from a nested directory", function()
    local root = vim.fn.tempname() .. "/ws-test"
    local nested = root .. "/apps/my-app/src"
    vim.fn.mkdir(nested, "p")
    local f = io.open(root .. "/nx.json", "w")
    f:write('{}')
    f:close()

    workspace.reset()
    local found = workspace.detect(nested)
    t.assert_eq(root, found)

    vim.fn.delete(root, "rf")
  end)

  t.it("returns nil when no nx.json exists", function()
    workspace.reset()
    local found = workspace.detect("/tmp")
    t.assert_eq(nil, found)
  end)

  t.it("caches the workspace root after first detection", function()
    local root = vim.fn.tempname() .. "/ws-cache"
    vim.fn.mkdir(root, "p")
    local f = io.open(root .. "/nx.json", "w")
    f:write('{}')
    f:close()

    workspace.reset()
    local first = workspace.detect(root)
    -- Remove nx.json — should still return cached value
    os.remove(root .. "/nx.json")
    local second = workspace.detect(root .. "/sub")
    t.assert_eq(first, second)

    vim.fn.delete(root, "rf")
  end)
end)

t.describe("workspace.nx_bin", function()
  t.it("returns npx nx when no local binary found", function()
    workspace.reset()
    -- Force a known root with no node_modules
    local root = vim.fn.tempname() .. "/ws-bin"
    vim.fn.mkdir(root, "p")
    local f = io.open(root .. "/nx.json", "w")
    f:write('{}')
    f:close()
    workspace.detect(root)

    local bin = workspace.nx_bin()
    t.assert_eq("npx nx", bin)

    vim.fn.delete(root, "rf")
  end)
end)

t.done()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u tests/minimal_init.lua -l tests/nx/workspace_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement workspace.lua**

```lua
-- lua/nx/workspace.lua
local utils = require("nx.utils")
local config = require("nx.config")

local M = {}

local state = {
  root = nil,
  detected_at = nil,
  nx_bin_path = nil,
}

--- Detect the Nx workspace root by walking up from `start_dir`.
--- Caches the result for the session (until reset or TTL expires).
--- @param start_dir? string defaults to cwd
--- @return string|nil root path or nil if not an Nx workspace
function M.detect(start_dir)
  start_dir = start_dir or vim.fn.getcwd()

  -- Return cached value if still valid
  if state.root and state.detected_at then
    local ttl = config.get().workspace.cache_ttl
    if (vim.uv.now() - state.detected_at) / 1000 < ttl then
      return state.root
    end
  end

  local root = utils.find_up("nx.json", start_dir)
  if root then
    state.root = root
    state.detected_at = vim.uv.now()
    state.nx_bin_path = nil -- reset so it re-detects
  end
  return root
end

--- Return the cached workspace root, or nil.
--- @return string|nil
function M.root()
  return state.root
end

--- Determine the nx binary to use.
--- Prefers local node_modules/.bin/nx, falls back to "npx nx".
--- @return string
function M.nx_bin()
  if state.nx_bin_path then
    return state.nx_bin_path
  end

  if state.root then
    local local_nx = state.root .. "/node_modules/.bin/nx"
    if vim.fn.executable(local_nx) == 1 then
      state.nx_bin_path = local_nx
      return local_nx
    end
  end

  state.nx_bin_path = "npx nx"
  return "npx nx"
end

--- Build a command table for running nx with given args.
--- @param args string[] args to pass to nx (e.g., {"show", "projects", "--json"})
--- @return string[] command table suitable for vim.system()
function M.nx_cmd(args)
  local bin = M.nx_bin()
  if bin == "npx nx" then
    local cmd = { "npx", "nx" }
    vim.list_extend(cmd, args)
    return cmd
  else
    local cmd = { bin }
    vim.list_extend(cmd, args)
    return cmd
  end
end

function M.reset()
  state.root = nil
  state.detected_at = nil
  state.nx_bin_path = nil
end

return M
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `nvim --headless -u tests/minimal_init.lua -l tests/nx/workspace_spec.lua`
Expected: All passed

- [ ] **Step 5: Commit**

```bash
git add lua/nx/workspace.lua tests/nx/workspace_spec.lua
git commit -m "feat: workspace detection with caching and nx binary resolution"
```

---

## Task 4: Notify module

**Files:**
- Create: `lua/nx/notify.lua`

- [ ] **Step 1: Implement notify.lua**

This is a thin wrapper — no tests needed beyond integration. It gracefully falls back if Snacks is unavailable.

```lua
-- lua/nx/notify.lua
local M = {}

local function has_snacks()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks or nil
end

--- @param msg string
--- @param level? number vim.log.levels (default INFO)
function M.info(msg, level)
  local snacks = has_snacks()
  if snacks and snacks.notifier then
    snacks.notifier.notify(msg, {
      level = level or vim.log.levels.INFO,
      title = "Nx",
    })
  else
    vim.notify("[Nx] " .. msg, level or vim.log.levels.INFO)
  end
end

function M.warn(msg)
  M.info(msg, vim.log.levels.WARN)
end

function M.error(msg)
  M.info(msg, vim.log.levels.ERROR)
end

return M
```

- [ ] **Step 2: Commit**

```bash
git add lua/nx/notify.lua
git commit -m "feat: notify module wrapping Snacks.notifier with fallback"
```

---

## Task 5: Projects data layer

**Files:**
- Create: `lua/nx/projects.lua`
- Create: `tests/nx/projects_spec.lua`

- [ ] **Step 1: Write failing test for parsing project list JSON**

The actual `nx show projects --json` call requires an Nx workspace. We test the *parsing* logic separately from the CLI call so tests don't need a real workspace.

```lua
-- tests/nx/projects_spec.lua
local t = require("tests.test_helper")
local projects = require("nx.projects")

-- Sample data that `nx show projects --json` returns (array of project names)
local sample_project_list = '["my-app","ui-components","data-access-users"]'

-- Sample data that `nx show project <name> --json` returns
local sample_project_detail = [[{
  "name": "my-app",
  "root": "apps/my-app",
  "projectType": "application",
  "targets": {
    "build": { "executor": "@nx/webpack:webpack" },
    "serve": { "executor": "@nx/webpack:dev-server" },
    "test": { "executor": "@nx/jest:jest" },
    "lint": { "executor": "@nx/eslint:lint" }
  }
}]]

t.describe("projects.parse_project_list", function()
  t.it("parses JSON array of project names", function()
    local result = projects.parse_project_list(sample_project_list)
    t.assert_eq(3, #result)
    t.assert_eq("my-app", result[1])
    t.assert_eq("ui-components", result[2])
  end)

  t.it("returns empty table on invalid JSON", function()
    local result = projects.parse_project_list("not json")
    t.assert_eq(0, #result)
  end)
end)

t.describe("projects.parse_project_detail", function()
  t.it("parses project detail JSON", function()
    local detail = projects.parse_project_detail(sample_project_detail)
    t.assert_eq("my-app", detail.name)
    t.assert_eq("apps/my-app", detail.root)
    t.assert_eq("application", detail.type)
    t.assert_eq(4, #detail.targets)
  end)

  t.it("extracts target names and executors", function()
    local detail = projects.parse_project_detail(sample_project_detail)
    local build = nil
    for _, tgt in ipairs(detail.targets) do
      if tgt.name == "build" then build = tgt end
    end
    t.assert_true(build ~= nil, "expected to find build target")
    t.assert_eq("@nx/webpack:webpack", build.executor)
  end)

  t.it("classifies project type correctly", function()
    local detail = projects.parse_project_detail(sample_project_detail)
    t.assert_eq("application", detail.type)
  end)
end)

t.done()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u tests/minimal_init.lua -l tests/nx/projects_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement projects.lua**

```lua
-- lua/nx/projects.lua
local utils = require("nx.utils")
local workspace = require("nx.workspace")
local notify = require("nx.notify")

local M = {}

local cache = {
  project_names = nil,
  project_details = {},
  fetched_at = nil,
}

--- Parse the JSON output of `nx show projects --json`.
--- @param json_str string
--- @return string[] project names
function M.parse_project_list(json_str)
  local ok, decoded = pcall(vim.json.decode, json_str)
  if not ok or type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

--- Parse the JSON output of `nx show project <name> --json`.
--- @param json_str string
--- @return { name: string, root: string, type: string, targets: { name: string, executor: string }[] }
function M.parse_project_detail(json_str)
  local ok, raw = pcall(vim.json.decode, json_str)
  if not ok or type(raw) ~= "table" then
    return { name = "", root = "", type = "library", targets = {} }
  end

  local targets = {}
  if raw.targets then
    for name, def in pairs(raw.targets) do
      table.insert(targets, {
        name = name,
        executor = def.executor or "",
      })
    end
    table.sort(targets, function(a, b) return a.name < b.name end)
  end

  return {
    name = raw.name or "",
    root = raw.root or "",
    type = raw.projectType or "library",
    targets = targets,
  }
end

--- Fetch all project names asynchronously.
--- @param callback fun(names: string[])
function M.list(callback)
  local root = workspace.root()
  if not root then
    notify.warn("No Nx workspace detected")
    callback({})
    return
  end

  local cmd = workspace.nx_cmd({ "show", "projects", "--json" })
  utils.exec(cmd, function(stdout)
    local names = M.parse_project_list(stdout)
    cache.project_names = names
    callback(names)
  end, function(err)
    notify.error("Failed to list projects: " .. (err or "unknown error"))
    callback({})
  end)
end

--- Fetch detail for a single project asynchronously.
--- @param name string project name
--- @param callback fun(detail: table)
function M.detail(name, callback)
  if cache.project_details[name] then
    callback(cache.project_details[name])
    return
  end

  local cmd = workspace.nx_cmd({ "show", "project", name, "--json" })
  utils.exec(cmd, function(stdout)
    local detail = M.parse_project_detail(stdout)
    cache.project_details[name] = detail
    callback(detail)
  end, function(err)
    notify.error("Failed to get project " .. name .. ": " .. (err or "unknown error"))
    callback({ name = name, root = "", type = "library", targets = {} })
  end)
end

--- Clear all cached data.
function M.reset()
  cache.project_names = nil
  cache.project_details = {}
  cache.fetched_at = nil
end

return M
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `nvim --headless -u tests/minimal_init.lua -l tests/nx/projects_spec.lua`
Expected: All passed

- [ ] **Step 5: Commit**

```bash
git add lua/nx/projects.lua tests/nx/projects_spec.lua
git commit -m "feat: projects data layer with async fetch and JSON parsing"
```

---

## Task 6: Task runner

**Files:**
- Create: `lua/nx/runner.lua`

- [ ] **Step 1: Implement runner.lua**

The runner depends on `Snacks.terminal` which requires a running Neovim GUI, so we test it via integration only. The logic is minimal — it builds a command string and delegates to Snacks.

```lua
-- lua/nx/runner.lua
local workspace = require("nx.workspace")
local config = require("nx.config")
local notify = require("nx.notify")

local M = {}

--- Run an nx target.
--- @param project string project name
--- @param target string target name
--- @param extra_args? string additional CLI flags
function M.run(project, target, extra_args)
  local root = workspace.root()
  if not root then
    notify.warn("No Nx workspace detected")
    return
  end

  local cfg = config.get().runner
  local cmd = workspace.nx_bin() .. " run " .. project .. ":" .. target
  if extra_args and extra_args ~= "" then
    cmd = cmd .. " " .. extra_args
  end

  local ok, snacks = pcall(require, "snacks")
  if not ok then
    notify.error("snacks.nvim is required for the task runner")
    return
  end

  local icons = config.get().icons
  local label = project .. ":" .. target

  local opts = {
    cwd = root,
    interactive = false,
    auto_close = false,
  }

  if cfg.terminal_style == "float" then
    opts.win = {
      style = "terminal",
      position = "float",
      width = cfg.float_width,
      height = cfg.float_height,
      title = " " .. icons.nx .. " " .. cmd .. " ",
      border = "rounded",
    }
  elseif cfg.terminal_style == "split" then
    opts.win = {
      style = "terminal",
      position = "bottom",
    }
  elseif cfg.terminal_style == "vsplit" then
    opts.win = {
      style = "terminal",
      position = "right",
    }
  end

  local start_time = vim.uv.now()
  notify.info(icons.running .. " Running " .. label)

  local term = snacks.terminal(cmd, opts)

  -- Wire up completion notification via TermClose event
  if cfg.notify_on_complete and term and term.buf then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = term.buf,
      once = true,
      callback = function()
        local elapsed = (vim.uv.now() - start_time) / 1000
        local duration = string.format("%.1fs", elapsed)
        local exit_code = vim.v.event and vim.v.event.status or -1
        if exit_code == 0 then
          notify.info(icons.success .. " " .. label .. " completed in " .. duration)
        else
          notify.error(icons.failure .. " " .. label .. " failed (exit " .. exit_code .. ") in " .. duration)
        end
      end,
    })
  end
end

return M
```

- [ ] **Step 2: Commit**

```bash
git add lua/nx/runner.lua
git commit -m "feat: task runner via Snacks.terminal with float/split support"
```

---

## Task 7: Pickers — project + target selection

**Files:**
- Create: `lua/nx/pickers.lua`

- [ ] **Step 1: Implement pickers.lua**

```lua
-- lua/nx/pickers.lua
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
            -- Refresh the preview if picker is still open
            if ctx.preview then
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
          end)
          -- Show loading text while fetching
          ctx.preview:set_lines({ "Loading project details..." })
          return
        end

        local detail = item._detail
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
      end,
      confirm = function(picker, item)
        picker:close()
        M.targets(item.project_name)
      end,
    })
  end)
end

return M
```

- [ ] **Step 2: Commit**

```bash
git add lua/nx/pickers.lua
git commit -m "feat: project and target pickers via Snacks.picker"
```

---

## Task 8: Wire up init.lua — commands, keymaps, autocommands

**Files:**
- Modify: `lua/nx/init.lua`
- Create: `plugin/nx.lua`

- [ ] **Step 1: Complete init.lua with public API, commands, and keymaps**

```lua
-- lua/nx/init.lua
local config = require("nx.config")
local workspace = require("nx.workspace")

local M = {}

function M.setup(opts)
  config.setup(opts)

  local cfg = config.get()

  -- Register user commands
  vim.api.nvim_create_user_command("NxProjects", function()
    require("nx.pickers").projects()
  end, { desc = "Nx: project + target picker" })

  vim.api.nvim_create_user_command("NxRefresh", function()
    require("nx.projects").reset()
    workspace.reset()
    workspace.detect()
    require("nx.notify").info("Workspace cache refreshed")
  end, { desc = "Nx: refresh workspace cache" })

  -- Register keymaps
  local keys = cfg.keys
  if keys.projects then
    vim.keymap.set("n", keys.projects, "<cmd>NxProjects<cr>", { desc = "Nx: projects" })
  end
  if keys.refresh then
    vim.keymap.set("n", keys.refresh, "<cmd>NxRefresh<cr>", { desc = "Nx: refresh" })
  end

  -- which-key integration
  local wk_ok, wk = pcall(require, "which-key")
  if wk_ok then
    wk.add({ { "<leader>n", group = "Nx" } })
  end

  -- Auto-detect workspace on setup
  if cfg.workspace.auto_detect then
    workspace.detect()
  end
end

--- Return the workspace root, or nil.
--- @return string|nil
function M.workspace_root()
  return workspace.root()
end

return M
```

- [ ] **Step 2: Create plugin/nx.lua autocommand trigger**

```lua
-- plugin/nx.lua
-- Autocommand for workspace detection on BufEnter.
-- This file is loaded automatically by Neovim's plugin system.
-- It only sets up the autocommand; actual plugin init happens via require("nx").setup().

vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("NxWorkspaceDetect", { clear = true }),
  callback = function()
    -- Skip special buffers (terminals, help, quickfix, etc.)
    if vim.bo.buftype ~= "" then return end

    -- Only run if setup() has been called (config exists)
    local ok, config = pcall(require, "nx.config")
    if not ok then return end
    local cfg = config.get()
    if not cfg.workspace.auto_detect then return end

    local ws = require("nx.workspace")
    local buf_dir = vim.fn.expand("%:p:h")
    if buf_dir and buf_dir ~= "" then
      ws.detect(buf_dir)
    end
  end,
})
```

- [ ] **Step 3: Commit**

```bash
git add lua/nx/init.lua plugin/nx.lua
git commit -m "feat: wire up public API, commands, keymaps, and BufEnter autocommand"
```

---

## Task 9: Run all tests, verify everything works

- [ ] **Step 1: Run full test suite**

```bash
nvim --headless -u tests/minimal_init.lua -l tests/nx/config_spec.lua
nvim --headless -u tests/minimal_init.lua -l tests/nx/utils_spec.lua
nvim --headless -u tests/minimal_init.lua -l tests/nx/workspace_spec.lua
nvim --headless -u tests/minimal_init.lua -l tests/nx/projects_spec.lua
```

All should pass.

- [ ] **Step 2: Manual smoke test**

Open nvim in an actual Nx workspace with this plugin on the rtp:
```bash
nvim --cmd "set rtp+=path/to/nx.nvim" -c "lua require('nx').setup({})" .
```

Verify:
1. `:NxProjects` opens the picker (requires snacks.nvim)
2. Selecting a project opens target picker
3. Selecting a target runs via Snacks.terminal
4. `:NxRefresh` clears cache and re-detects

- [ ] **Step 3: Final commit if any fixes needed**

---

## Summary

| Task | What it produces |
|---|---|
| 1 | Config module + setup scaffold + test harness |
| 2 | Async exec wrapper + find_up utility |
| 3 | Workspace detection with caching |
| 4 | Notification wrappers |
| 5 | Project data layer (list + detail + parsing) |
| 6 | Task runner via Snacks.terminal |
| 7 | Project + target pickers |
| 8 | Public API, commands, keymaps, autocommands |
| 9 | Full test run + smoke test |
