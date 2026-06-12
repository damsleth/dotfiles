-- Apply a scheme based on a "dark" boolean: dark -> "vim", light -> "morning".
local function apply(dark)
  vim.o.background = dark and "dark" or "light"
  vim.cmd.colorscheme(dark and "vim" or "morning")
end

-- Synchronous OS-appearance check. Returns true for dark (or when unknown).
local function is_dark()
  if vim.fn.has("mac") == 0 then
    return true
  end
  -- `AppleInterfaceStyle` is "Dark" when dark mode is on, and the key is
  -- absent (read errors) when it's off.
  return vim.fn.system("defaults read -g AppleInterfaceStyle 2>/dev/null"):match("Dark") ~= nil
end

-- Async re-check used by the autocmd so it never blocks the UI.
local function refresh()
  if vim.fn.has("mac") == 0 then
    return
  end
  vim.system({ "defaults", "read", "-g", "AppleInterfaceStyle" }, { text = true }, function(out)
    local dark = (out.stdout or ""):match("Dark") ~= nil
    vim.schedule(function()
      apply(dark)
    end)
  end)
end

-- Live-switch when the terminal/Neovim regains focus (e.g. after toggling the
-- OS theme). Event-driven and async, so there's no idle cost.
vim.api.nvim_create_autocmd("FocusGained", {
  group = vim.api.nvim_create_augroup("os_appearance", { clear = true }),
  callback = refresh,
})

return {
  {
    "LazyVim/LazyVim",
    -- Pick the scheme synchronously at startup from the OS appearance.
    opts = {
      colorscheme = function()
        apply(is_dark())
      end,
    },
  },
}
