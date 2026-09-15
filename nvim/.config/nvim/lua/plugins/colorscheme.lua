-- Neovim >=0.10 queries the terminal's background colour (OSC 11) at startup and
-- sets 'background' from it, so kitty's current theme decides light vs dark.
local function apply()
  vim.cmd.colorscheme(vim.o.background == "dark" and "vim" or "morning")
  -- ponytail: let kitty's background (and blur) show through.
  for _, g in ipairs({ "Normal", "NormalNC", "NormalFloat", "SignColumn", "LineNr", "EndOfBuffer" }) do
    vim.api.nvim_set_hl(0, g, { bg = "none" })
  end
end

-- Toggling the kitty theme mid-session: nvim re-queries on :set background& only,
-- so this just covers a manual `:set background=light`.
vim.api.nvim_create_autocmd("OptionSet", {
  pattern = "background",
  group = vim.api.nvim_create_augroup("term_appearance", { clear = true }),
  callback = apply,
})

return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = apply,
    },
  },
}
