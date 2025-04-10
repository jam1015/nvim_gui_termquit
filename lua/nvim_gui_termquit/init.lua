--- Neovim GUI Terminal and Quit Management Module
--- This module sets up a custom terminal behavior in Neovim and redefines quit commands
--- to safeguard a designated "main terminal" buffer. It provides functionality to:
---   - Automatically open a terminal if Neovim starts without file arguments.
---   - Switch the current directory based on an external file (configured in your shell).
---   - Intercept and override default commands like :q, :wq, :qa, and :wqa with custom logic.
---   - Jump to the marked terminal via a new command and mapping.
local M = {}

--- Sets up the module.
--- This function registers autocommands for starting a terminal on startup,
--- defines command-line abbreviations for quit commands, and creates custom user commands,
--- including the :Terminal command and a plug mapping.
--- @param opts table|nil Optional configuration table.
function M.setup(opts)
  opts = opts or {}

  --- Creates and opens a startup terminal if Neovim was launched without any file arguments.
  --- It reads the directory from a file (set in your shell configuration) and opens a terminal buffer.
  local function call_terminal()
    if #vim.fn.argv() == 0 then
      -- Expand path to the "whereami" file (this file is set in your zshrc)
      local file_path = vim.fn.expand("~/.local/state/zsh/whereami")
      local lines = vim.fn.readfile(file_path)
      if lines and #lines > 0 then
        local new_dir = lines[1]
        vim.api.nvim_set_current_dir(new_dir)
      end
      -- Disable list mode locally and open a terminal buffer
      vim.opt_local.list = false
      vim.cmd("terminal")
      vim.opt_local.number = false
      vim.opt_local.relativenumber = false
      vim.cmd("norm a") -- Enter insert mode in the terminal.
      local term_buf = vim.api.nvim_get_current_buf()
      -- Mark this terminal as the main terminal for later reference.
      vim.api.nvim_buf_set_var(term_buf, "is_main_terminal", true)
    end
  end

  -- Create an augroup for the GUI terminal autocommand and register the VimEnter event.
  local gui = vim.api.nvim_create_augroup("gui_terminal", { clear = true })
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = call_terminal,
    group = gui,
  })

  -- Set up command-line abbreviations to override default quit commands.
  vim.cmd([[
    cnoreabbrev <expr> q   getcmdtype() == ":" && getcmdline() == "q"   ? "Q"   : "q"
    cnoreabbrev <expr> wq  getcmdtype() == ":" && getcmdline() == "wq"  ? "WQ"  : "wq"
    cnoreabbrev <expr> Wq  getcmdtype() == ":" && getcmdline() == "Wq"  ? "WQ"  : "Wq"
    cnoreabbrev <expr> qa  getcmdtype() == ":" && getcmdline() == "qa"  ? "QA"  : "qa"
    cnoreabbrev <expr> Qa  getcmdtype() == ":" && getcmdline() == "Qa"  ? "QA"  : "Qa"
    cnoreabbrev <expr> wqa getcmdtype() == ":" && getcmdline() == "wqa" ? "WQA" : "wqa"
    cnoreabbrev <expr> wqa getcmdtype() == ":" && getcmdline() == "Wqa" ? "WQA" : "wqa"
    cnoreabbrev <expr> wqa getcmdtype() == ":" && getcmdline() == "WQa" ? "WQA" : "wqa"
  ]])

  -- Create custom user commands that utilize our safe_quit functionality.
  vim.api.nvim_create_user_command('Q', function(opts_in)
    require('nvim_gui_termquit').safe_quit('q', opts_in.bang)
  end, { bang = true })

  vim.api.nvim_create_user_command('WQ', function(opts_in)
    require('nvim_gui_termquit').safe_quit('wq', opts_in.bang)
  end, { bang = true })

  vim.api.nvim_create_user_command('QA', function(opts_in)
    require('nvim_gui_termquit').safe_quit('qa', opts_in.bang)
  end, { bang = true })

  vim.api.nvim_create_user_command('WQA', function(opts_in)
    require('nvim_gui_termquit').safe_quit('wqa', opts_in.bang)
  end, { bang = true })

  --- Create a new command :Terminal that jumps to the main terminal,
  --- entering terminal (insert) mode.
  vim.api.nvim_create_user_command('Terminal', function()
    M.goto_terminal()
  end, { desc = "Switch to the marked terminal and enter terminal mode" })

  --- Define a plug mapping (<Plug>GotoTerminal) that calls the Lua function to go to the terminal.
  vim.api.nvim_set_keymap('n', '<Plug>GotoTerminal', '<cmd>lua require("nvim_gui_termquit").goto_terminal()<CR>',
    { noremap = true, silent = true })
end

--- Finds all terminal buffers that are marked as the main terminal.
--- @return table List of buffer numbers that are considered the main terminal.
local function find_marked_term()
  local marked_buffers = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == 'terminal' then
      local ok, is_marked = pcall(vim.api.nvim_buf_get_var, bufnr, "is_main_terminal")
      if ok and is_marked then
        table.insert(marked_buffers, bufnr)
      end
    end
  end
  return marked_buffers
end

--- Safely sets the current buffer.
--- If an error occurs, it notifies the user.
--- @param bufnr number The buffer number to switch to.
local function safe_set_buf(bufnr)
  local ok, err = pcall(vim.api.nvim_set_current_buf, bufnr)
  if not ok then
    vim.notify(err, vim.log.levels.WARN)
  end
end

--- Writes all modified (non-terminal) buffers.
--- @param bang boolean Whether to use a forced write command ("write!") instead of "write".
--- @return boolean True if all buffers were written successfully; false otherwise.
local function write_modded_buffers(bang)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype ~= 'terminal' then
      if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
        safe_set_buf(bufnr)
        local command = bang and "write!" or "write"
        local success, err = pcall(vim.cmd, command)
        if not success then
          vim.notify(err, vim.log.levels.WARN)
          return false
        end
      end
    else
      return false
    end
  end
  return true
end

--- Checks if a given buffer is a terminal and marked as the main terminal.
--- @param bufnr number The buffer number to check.
--- @return boolean True if the buffer is a terminal and is marked; false otherwise.
local function check_term_marked(bufnr)
  local is_marked = false
  if vim.bo[bufnr].buftype == 'terminal' then
    local ok, marked = pcall(vim.api.nvim_buf_get_var, bufnr, "is_main_terminal")
    if ok and marked then
      is_marked = true
    end
  end
  return is_marked
end

--- Deletes buffers that are not marked as the main terminal.
--- @param bang boolean Whether to force deletion (using force option).
--- @param all boolean If true, even buffers not loaded are considered for deletion.
--- @return boolean True if deletion was successful for all applicable buffers; false otherwise.
local function delete_unmarked_native(bang, all)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      safe_set_buf(bufnr)
      if not check_term_marked(bufnr) then
        local success, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = bang })
        if not success then
          vim.notify(err, vim.log.levels.WARN)
          return false
        end
      end
    else
      if not check_term_marked(bufnr) then
        safe_set_buf(bufnr)
        if all then
          local success, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = bang })
        else
          return false
        end
      end
    end
  end
  return true
end

--- Closes all tabs except the current one and all windows except the current window.
--- This function ensures that only one window remains after deletions.
local function only_window()
  -- Step 1: Close all other tabs.
  local current_tab = vim.api.nvim_get_current_tabpage()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab ~= current_tab then
      vim.api.nvim_tabpage_close(tab, true)
    end
  end

  -- Step 2: Close all other windows in the current tab.
  local current_win = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
    if win ~= current_win then
      vim.api.nvim_win_close(win, true)
    end
  end
end

--- Switches focus to the main terminal buffer.
--- It finds the first terminal buffer marked as the main terminal and sets it as current.
local function switch_to_main()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == 'terminal' then
      local ok, is_marked = pcall(vim.api.nvim_buf_get_var, bufnr, "is_main_terminal")
      if ok and is_marked then
        vim.api.nvim_set_current_buf(bufnr)
        return
      end
    end
  end
end

--- Checks if multiple windows are open in the current tab.
--- @return boolean True if more than one window is open; false otherwise.
local function has_multiple_windows()
  local wins = vim.api.nvim_tabpage_list_wins(0) -- 0 = current tabpage
  return #wins > 1
end

--- Checks if multiple tabs are open.
--- @return boolean True if more than one tab is open; false otherwise.
local function has_multiple_tabs()
  local tabs = vim.api.nvim_list_tabpages()
  return #tabs > 1
end

--- Safely quits buffers based on the requested command and optional bang flag.
--- The behavior varies depending on the command:
---   - 'wqa': Writes all modified non-terminal buffers and deletes unmarked buffers if a main terminal is found.
---   - 'qa': Deletes unmarked buffers without writing modifications if a main terminal is found.
---   - 'wq': Writes modifications and deletes unmarked buffers only if a single window/tab with a main terminal exists.
---   - 'q': Quits the current buffer or deletes unmarked buffers based on context.
---
--- @param cmd string The quit command ('q', 'wq', 'qa', or 'wqa').
--- @param bang boolean Whether the command was invoked with a bang (!) to force actions.
function M.safe_quit(cmd, bang)
  local marked_buffers = find_marked_term()
  if cmd == 'wqa' then
    if #marked_buffers > 0 then
      if write_modded_buffers(bang) and delete_unmarked_native(bang, true) then
        only_window()
      end
    else
      local command = cmd
      if bang then command = command .. "!" end
      vim.cmd(command)
    end
    return
  end

  if cmd == 'qa' then
    if #marked_buffers > 0 then
      if delete_unmarked_native(bang, true) then
        only_window()
        return
      end
    else
      local command = cmd
      if bang then command = command .. "!" end
      vim.cmd(command)
      return
    end
    return
  end

  if cmd == 'wq' then
    -- If a main terminal exists and there's a single tab and window,
    -- write modified buffers, delete unmarked buffers, and switch to the main terminal.
    if #marked_buffers > 0 and not has_multiple_tabs() and not has_multiple_windows() then
      write_modded_buffers(bang)
      delete_unmarked_native(bang, false)
      switch_to_main()
    else
      local command = cmd
      if bang then command = command .. "!" end
      local success, err = pcall(vim.cmd, command)
      if not success then
        vim.notify(err, vim.log.levels.WARN)
      end
    end
    return
  end

  if cmd == 'q' then
    if #marked_buffers > 0 and not has_multiple_tabs() and not has_multiple_windows() then
      delete_unmarked_native(bang, false)
    else
      local command = cmd
      if bang then command = command .. "!" end
      vim.cmd(command)
    end
    return
  end
end

--- Switches to the marked terminal or returns to the origin buffer.
---
--- When called from a non-terminal buffer, this function:
---   1. Uses the helper function `find_marked_term()` to locate the main terminal buffer.
---   2. Records the current buffer as the "origin_buffer" in the marked terminal.
---   3. Switches to the marked terminal and enters terminal (insert) mode.
---
--- When called from within the marked terminal, it attempts to:
---   1. Retrieve the recorded "origin_buffer".
---   2. Switch back to that origin buffer if it exists and is loaded.
---   3. Otherwise, it notifies the user that no valid origin buffer is available.
---
--- @return nil
function M.goto_terminal()
  local cur_buf = vim.api.nvim_get_current_buf()
  local is_cur_marked = false

  -- Check if the current buffer is a terminal and marked as the main terminal.
  if vim.bo[cur_buf].buftype == 'terminal' then
    local ok, is_main = pcall(vim.api.nvim_buf_get_var, cur_buf, "is_main_terminal")
    if ok and is_main then
      is_cur_marked = true
    end
  end

  if is_cur_marked then
    -- If we're already in the marked terminal, try to jump back to the origin.
    local ok, origin_buf = pcall(vim.api.nvim_buf_get_var, cur_buf, "origin_buffer")
    if ok and origin_buf and vim.api.nvim_buf_is_loaded(origin_buf) then
      vim.api.nvim_set_current_buf(origin_buf)
    else
      vim.notify("No origin buffer recorded or it is no longer available.", vim.log.levels.WARN)
    end
  else
    -- Use the provided helper function to find the marked terminal(s).
    local marked_buffers = find_marked_term()
    if #marked_buffers > 0 then
      local main_term_buf = marked_buffers[1]
      -- Record the current (origin) buffer in the terminal buffer.
      vim.api.nvim_buf_set_var(main_term_buf, "origin_buffer", cur_buf)
      vim.api.nvim_set_current_buf(main_term_buf)
    else
      vim.notify("No marked terminal found", vim.log.levels.WARN)
    end
  end
end

return M
