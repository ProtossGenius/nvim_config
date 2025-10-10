# Neovim Keymap Cheatsheet

This document outlines the primary keybindings configured in your Neovim setup. Your leader key is `Space`.

## Language Server Protocol (LSP)

These features are available when a language server is attached to the buffer.

| Keybinding | Action | Description |
| :--- | :--- | :--- |
| `gd` | Go to Definition | Jumps to the definition of the symbol under the cursor. |
| `gr` | Go to References | Shows all references to the symbol under the cursor. |
| `gD` | Go to Declaration | Jumps to the declaration of the symbol under the cursor. |
| `K` | Hover | Displays hover information (e.g., type definitions, documentation) for the symbol under the cursor. |
| `<leader>ca` | Code Action | Triggers a menu of available code actions (e.g., auto-imports, refactoring options). |
| `<leader>rn` | Rename | Renames the symbol under the cursor and all its references. |

## Fuzzy Finding (Telescope)

| Keybinding | Action | Description |
| :--- | :--- | :--- |
| `<C-p>` | Find Files | Opens a fuzzy finder to search for files in the current directory. |
| `<leader>fg` | Live Grep | Performs a live grep search for a string within all files. |
| `<leader>fb` | Find Buffers | Fuzzy finds through all open buffers. |
| `<leader>fh` | Help Tags | Searches through Neovim's help tags. |
| `<leader>ff` | Find Git Files | Fuzzy finds through all files tracked by Git. |

## Autocompletion

These keybindings are active in insert mode.

| Keybinding | Action | Description |
| :--- | :--- | :--- |
| `<C-Space>` | Complete | Triggers the autocompletion menu. |
| `<C-n>` | Next Item | Selects the next item in the completion menu. |
| `<C-p>` | Previous Item | Selects the previous item in the completion menu. |
| `<C-y>` | Confirm | Confirms the selected completion. |