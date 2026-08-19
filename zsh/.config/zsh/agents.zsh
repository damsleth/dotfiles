# agent-specific aliases, functions and completions
alias clauded="claude --allow-dangerously-skip-permissions" # Claude in yolo-mode
alias claudeh="headroom wrap claude"
alias claudedh="headroom wrap claude --allow-dangerously-skip-permissions" # Claude in yolo-mode
alias codexh="headroom wrap codex"
alias codexdh="headroom wrap codex --dangerously-bypass-approvals-and-sandbox" # Codex in yolo-mode
alias codexd="codex --dangerously-bypass-approvals-and-sandbox" # Codex in yolo-mode

# codex non-interactive, with no prompts, and just print the response.
codexq(){
  if [ $# -eq 0 ]; then
    echo "Usage: codexq <question>"
    return 1
  fi
  codex exec --model "gpt-5.4-mini" --sandbox read-only --skip-git-repo-check "$*"
}
