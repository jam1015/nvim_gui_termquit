local M = {}

function M.setup(opts)
  opts = opts or {}

  -- Create the startup terminal when no files are passed.
  local function call_terminal()
    if #vim.fn.argv() == 0 then
      -- this is set in my zshrc
      local file_path = vim.fn.expand("~/.local/state/zsh/whereami")
      local lines = vim.fn.readfile(file_path)
      if lines and #lines > 0 then
        local new_dir = lines[1]
        vim.api.nvim_set_current_dir(new_dir)
      end
      vim.opt_local.list = false
      vim.cmd("terminal")
      vim.cmd("norm a") -- Enter insert mode in the terminal.
      local term_buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_var(term_buf, "is_main_terminal", true)
    end
  end

  local gui = vim.api.nvim_create_augroup("gui_terminal", { clear = true })

  vim.api.nvim_create_autocmd("VimEnter", {
    callback = call_terminal,
    group = gui,
  })

  -- Set up command-line abbreviations with safeguards so they only trigger in : commands.
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


  -- Define commands using native Lua with the bang (!) flag.
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
end

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

local function safe_set_buf(bufnr)
  local ok, err = pcall(vim.api.nvim_set_current_buf, bufnr)
  if not ok then
    vim.notify(err, vim.log.levels.WARN)
  end
end

local function write_modded_buffers(bang)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype ~= 'terminal' then
      if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
        safe_set_buf(bufnr)
        local command = ""
        if bang then
          command = "write!"
        else
          command = "write"
        end
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


local function only_window()
  -- Step 1: Close all other tabs
  local current_tab = vim.api.nvim_get_current_tabpage()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab ~= current_tab then
      vim.api.nvim_tabpage_close(tab, true)
    end
  end

  -- Step 2: Close all other windows in the current tab
  local current_win = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
    if win ~= current_win then
      vim.api.nvim_win_close(win, true)
    end
  end
end
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


local function has_multiple_windows()
  local wins = vim.api.nvim_tabpage_list_wins(0) -- 0 = current tabpage
  return #wins > 1
end

local function has_multiple_tabs()
  local tabs = vim.api.nvim_list_tabpages()
  return #tabs > 1
end


--- Checks for the marked terminal.
--- For 'wqa': if found, writes all non-terminal buffers (if modified) and then calls :Bdelete on every
--- buffer except the marked terminal(s). If no marked terminal is found, proceeds with :wqa.
--- For 'qa': if a marked terminal is found, calls :Bdelete on every buffer except the marked terminal.
--- For other commands: if a marked terminal is found, switches to it instead of quitting.
--- Otherwise, executes the requested quit command.
---@param cmd string: 'q', 'wq', 'qa', or 'wqa'
---@param bang boolean: whether the command was called with a bang (!)
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
    -- find length of marked buffers
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
    -- find length of marked buffers
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

return M
