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
