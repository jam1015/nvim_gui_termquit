local M = {}

--- Sets up the Neovide safe quit functionality and startup terminal.
function M.setup(opts)
  opts = opts or {}

  -- Create the startup terminal when no files are passed.
  local function call_terminal()
    if #vim.fn.argv() == 0 then
      local file_path = vim.fn.expand("~/.local/state/zsh/whereami")
      local lines = vim.fn.readfile(file_path)
      if lines and #lines > 0 then
        local new_dir = lines[1]
        vim.cmd("cd " .. new_dir)
      end
      vim.cmd("terminal")
      vim.cmd("norm a") -- Enter insert mode in the terminal.
      local term_buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_var(term_buf, "is_neovide_terminal", true)
    end
  end

  local nvide = vim.api.nvim_create_augroup("neovide_terminal", { clear = true })
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = call_terminal,
    group = nvide,
  })

  -- Set up command-line abbreviations with safeguards so they only trigger in : commands.
  vim.cmd([[
    cnoreabbrev <expr> q   getcmdtype() == ":" && getcmdline() == "q"   ? "Q"   : "q"
    cnoreabbrev <expr> wq  getcmdtype() == ":" && getcmdline() == "wq"  ? "WQ"  : "wq"
    cnoreabbrev <expr> Wq  getcmdtype() == ":" && getcmdline() == "Wq"  ? "WQ"  : "Wq"
    cnoreabbrev <expr> qa  getcmdtype() == ":" && getcmdline() == "qa"  ? "QA"  : "qa"
    cnoreabbrev <expr> Qa  getcmdtype() == ":" && getcmdline() == "Qa"  ? "QA"  : "Qa"
  ]])

  -- Define commands that call our Lua safe_quit function.
  vim.cmd("command! Q   lua require('nvim_gui_termquit').safe_quit('q')")
  vim.cmd("command! WQ  lua require('nvim_gui_termquit').safe_quit('wq')")
  vim.cmd("command! QA  lua require('nvim_gui_termquit').safe_quit('qa')")
end

--- Checks for the marked terminal. If found, switches to it instead of quitting.
--- Otherwise, executes the requested quit command.
---@param cmd string: 'q', 'wq', or 'qa'
function M.safe_quit(cmd)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      if vim.bo[bufnr].buftype == 'terminal' then
        local ok, is_marked = pcall(vim.api.nvim_buf_get_var, bufnr, "is_neovide_terminal")
        if ok and is_marked then
          vim.cmd("buffer " .. bufnr)
          print("Neovide terminal is active. Switching to it instead of quitting.")
          return
        end
      end
    end
  end
  if cmd == 'wq' then
    vim.cmd("wq")
  elseif cmd == 'qa' then
    vim.cmd("qa")
  else
    vim.cmd("q")
  end
end

return M
