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
