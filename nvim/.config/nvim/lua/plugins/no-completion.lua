-- Disable all autocomplete / tab-complete functionality.
-- LazyVim uses blink.cmp as its completion engine; turning it off removes
-- the popup menu, ghost text, and the <Tab> completion mappings entirely.
return {
  { "saghen/blink.cmp", enabled = false },

  -- friendly-snippets only exists to feed the completion engine, so drop it too.
  { "rafamadriz/friendly-snippets", enabled = false },
}
