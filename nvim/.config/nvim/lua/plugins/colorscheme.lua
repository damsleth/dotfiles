-- Neovim >=0.10 queries the terminal's background colour (OSC 11) at startup and
-- sets 'background' from it, so kitty's current theme decides light vs dark.
local function apply()
  vim.cmd.colorscheme(vim.o.background == "dark" and "vim" or "morning")
  -- ponytail: let kitty's background (and blur) show through.
  for _, g in ipairs({ "Normal", "NormalNC", "NormalFloat", "SignColumn", "LineNr", "EndOfBuffer" }) do
    vim.api.nvim_set_hl(0, g, { bg = "none" })
  end
  -- The "vim" scheme's DiffText/ColorColumn are loud reds and blues, and
  -- render-markdown borrows them for headings and code. Calm greys instead.
  if vim.o.background == "dark" then
    for i = 1, 6 do
      vim.api.nvim_set_hl(0, "RenderMarkdownH" .. i, { fg = "#87afd7", bold = true })
      vim.api.nvim_set_hl(0, "RenderMarkdownH" .. i .. "Bg", { bg = i == 1 and "#303030" or "#262626" })
    end
    vim.api.nvim_set_hl(0, "RenderMarkdownCode", { bg = "#1c1c1c" })
    vim.api.nvim_set_hl(0, "RenderMarkdownCodeInline", { fg = "#d7d7af", bg = "#262626" })
    vim.api.nvim_set_hl(0, "@markup.quote", { fg = "#a8a8a8", italic = true })
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
