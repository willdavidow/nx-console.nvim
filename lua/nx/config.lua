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
    long_running_targets = { "serve", "dev", "start", "watch" },
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

function M.is_setup()
  return current ~= nil
end

function M.reset()
  current = nil
end

return M
