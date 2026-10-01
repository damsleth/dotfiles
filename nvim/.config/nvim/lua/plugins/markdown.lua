return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      heading = {
        -- Turns on structural rendering
        enabled = true,
        -- Uses Kitty's text sizing protocol to physically alter font sizes
        -- by overriding the rendering highlights with terminal scaling sequences
        sign = false,
        -- Enforces distinct font scaling sizes across headings
        -- 1.4 means 40% larger, 1.2 means 20% larger, etc.
        sizes = { 3, 2, 1.5, 1.3, 1.2, 1.0 },
      },
      -- Hides the syntax markdown marks (e.g., # or ##) when not editing the line
      anti_conceal = {
        enabled = true,
      },
    },
  },
}
