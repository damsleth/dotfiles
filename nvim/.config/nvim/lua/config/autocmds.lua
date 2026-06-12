-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Kill LazyVim's wrap_spell autocmd that turns on `spell` for text/markdown/gitcommit/etc.
pcall(vim.api.nvim_del_augroup_by_name, "lazyvim_wrap_spell")

-- Belt and suspenders: force spell off whenever any buffer/window opens,
-- so nothing (plugins, filetype plugins) can re-enable the squigglies.
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType", "WinEnter" }, {
  group = vim.api.nvim_create_augroup("kill_spell", { clear = true }),
  callback = function()
    vim.opt_local.spell = false
  end,
})
