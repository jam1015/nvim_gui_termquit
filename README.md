# nvim_gui_termquit

The Neovide termquit Plugin is a Lua-based Neovim plugin designed
specifically for using Neovim GUI clients as terminal emulators. It 
provides a safe quit mechanism to
prevent accidental closure of Neovide when a special startup terminal is
active.

## Features

-   **Automatic Startup Terminal:** When Neovide is launched without
    file arguments, a terminal buffer is automatically opened and
    marked.
-   **Safe Quit Logic:** Overrides quit commands (`:q`, `:wq`, `:qa`) to
    check for the marked terminal. If the terminal is active, focus is
    switched to it instead of closing Neovide.
-   **Command Abbreviations:** Uses command-line abbreviations (with
    safeguards) so that lower-case commands are automatically mapped to
    their uppercase versions (`:W`, `:WQ`, `:QA`) which trigger the safe
    quit logic.
-   **Lua Module:** Packaged as a Lua module for easy integration and
    potential packaging as a plugin.

# Note

This relies on a [zsh hook in my personal config](https://github.com/jam1015/dotfiles/blob/master/.zshrc_personal#L154C1-L167C2) that sets the file `/.local/state/zsh/whereami` to contain the path to the last directory I switched to. 


## Installation


[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
     {
      'jam1015/nvim_gui_termquit',
      dependencies = {"famiu/bufdelete.nvim"},
      config = function()
        require('nvim_gui_termquit').setup()
      end
    }
```

## Usage

Add the following line to your `init.lua` (or your main configuration
file) to initialize the plugin:

    require('nvim_gui_termquit').setup()

When Neovide is started with no file arguments, the plugin will:

-   Read the directory from `~/.local/state/zsh/whereami` and change to
    that directory.
-   Open a terminal buffer and enter insert mode.
-   Mark that terminal buffer with a buffer-local variable.

The plugin also sets up command-line abbreviations such that typing:

-   `:w` is converted to `:W`
-   `:wq` or `:Wq` are converted to `:WQ`
-   `:qa` or `:Qa` are converted to `:QA`

The uppercase commands are defined as:

-   `:Q` -- Calls the safe quit function with the `'q'` argument.
-   `:WQ` -- Calls the safe quit function with the `'wq'` argument.
-   `:QA` -- Calls the safe quit function with the `'qa'` argument
    (which then calls `:qa` if no terminal is marked).
-   `:W` -- Simply writes the file (`:w`).

## Commands

-   `:Q` -- Invokes `require('nvim_gui_termquit').safe_quit('q')`. If the
    marked terminal is active, focus is switched to it; otherwise, it
    executes `:q`.
-   `:WQ` -- Invokes `require('nvim_gui_termquit').safe_quit('wq')`. If the
    marked terminal is active, focus is switched; otherwise, it performs
    `:wq`.
-   `:QA` -- Invokes `require('nvim_gui_termquit').safe_quit('qa')`. If the
    marked terminal is active, focus is switched; otherwise, it executes
    `:qa`.
-   `:W` -- Simply writes the file using `:w`.

## License

This plugin is released under the MIT License.

