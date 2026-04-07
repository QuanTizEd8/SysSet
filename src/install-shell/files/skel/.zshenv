# ~/.zshenv: sourced for EVERY zsh invocation — interactive, non-interactive,
# login, scripts, cron jobs, and remote commands over SSH.
#
# Keep this file minimal and side-effect-free. Output (echo, printf) and
# anything that depends on a terminal WILL break scripts and scp/rsync.
#
# Appropriate content:
#   - User-specific environment variables that must be available everywhere:
#       export MY_TOKEN="..."
#   - PATH additions for personal tools (keep them additive, not replacing):
#       export PATH="$HOME/.cargo/bin:$PATH"
#
# Do NOT put here: aliases, prompt config, key bindings, completions,
# or anything that sources files with output. Those belong in ~/.zshrc.
