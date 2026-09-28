-- ponytail: optional deps skipped; LazyVim's mini.icons mocks nvim-web-devicons, budoux is CJK-only
return {
  "delphinus/md-render.nvim",
  version = "*",
  keys = {
    { "<leader>mp", "<Plug>(md-render-preview)", desc = "Markdown preview (toggle)" },
    { "<leader>mt", "<Plug>(md-render-preview-tab)", desc = "Markdown preview in tab (toggle)" },
    { "<leader>md", "<Plug>(md-render-demo)", desc = "Markdown render demo" },
  },
}
