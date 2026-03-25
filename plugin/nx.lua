-- Autocommand for workspace detection on BufEnter.
-- This file is loaded automatically by Neovim's plugin system.
-- It only sets up the autocommand; actual plugin init happens via require("nx").setup().

vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("NxWorkspaceDetect", { clear = true }),
  callback = function()
    -- Skip special buffers (terminals, help, quickfix, etc.)
    if vim.bo.buftype ~= "" then return end

    -- Only run if setup() has been called
    local ok, config = pcall(require, "nx.config")
    if not ok or not config.is_setup() then return end
    local cfg = config.get()
    if not cfg.workspace.auto_detect then return end

    local ws = require("nx.workspace")
    local buf_dir = vim.fn.expand("%:p:h")
    if buf_dir and buf_dir ~= "" then
      ws.detect(buf_dir)
    end
  end,
})
