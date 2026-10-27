#!/usr/bin/env bash
# Remove the Trimtab beta: ~/.trimtab/app, the `trimtab` link, the PATH line the installer added, and uv if the installer
# put it there. Your data in ~/.trimtab (settings, API keys, history) is kept unless you say otherwise:
#   interactive terminal: it asks (default: keep)      curl ... | bash: keeps it and tells you how to delete it
#   --all: delete the data too (no question)
set -euo pipefail

APP_HOME="$HOME/.trimtab"
APP="$APP_HOME/app"
BIN="$HOME/.local/bin"
RC_BEGIN="# >>> trimtab (added by the installer)"
RC_END="# <<< trimtab"
say() { printf '%s\n' "$*"; }

ALL=false; [ "${1:-}" = "--all" ] && ALL=true
UV_BY_US=false
grep -q '"uv_installed_by_trimtab": true' "$APP_HOME/install.json" 2>/dev/null && UV_BY_US=true

# the command link, only if it is ours
if [ -L "$BIN/trimtab" ] && [ "$(readlink "$BIN/trimtab")" = "$APP/bin/trimtab" ]; then rm -f "$BIN/trimtab"; say "Removed $BIN/trimtab"; fi
if [ -d "$APP" ]; then rm -rf "$APP"; say "Removed $APP"; fi

# the PATH block, in whichever rc file has it
for rc in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
  if grep -qF "$RC_BEGIN" "$rc" 2>/dev/null; then
    tmp="$(mktemp)"
    awk -v b="$RC_BEGIN" -v e="$RC_END" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$rc" > "$tmp" && cat "$tmp" > "$rc"
    rm -f "$tmp"; say "Removed the PATH line from $rc"
    # a file the installer created and nothing else uses is removed too
    [ -z "$(tr -d '[:space:]' < "$rc")" ] && rm -f "$rc"
  fi
done

# uv, only when the installer installed it (and the Pythons / cache it fetched for us)
if [ "$UV_BY_US" = true ]; then
  for link in "$BIN"/python3*; do   # python3.11 shims that uv put next to itself
    [ -L "$link" ] && case "$(readlink "$link")" in "$HOME/.local/share/uv/"*) rm -f "$link" ;; esac
  done
  rm -f "$BIN/uv" "$BIN/uvx"; rm -rf "$HOME/.local/share/uv" "$HOME/.cache/uv"
  rm -f "$HOME/.config/uv/uv-receipt.json"
  rmdir "$HOME/.config/uv" "$HOME/.config" "$HOME/.cache" "$BIN" "$HOME/.local/share" "$HOME/.local" 2>/dev/null || true
  say "Removed uv (the installer had added it)"
fi
rm -f "$APP_HOME/install.json"

# the data
if [ "$ALL" = false ] && [ -d "$APP_HOME" ] && [ -t 0 ] && [ -t 1 ]; then
  printf 'Also delete your Trimtab data (settings, API keys, history in %s)? [y/N] ' "$APP_HOME"
  read -r answer || answer=""
  case "$answer" in y|Y|yes|YES) ALL=true ;; esac
fi
if [ "$ALL" = true ]; then
  rm -rf "$APP_HOME"; say "Removed $APP_HOME (all your Trimtab data)"
elif [ -d "$APP_HOME" ]; then
  say "Kept your data in $APP_HOME. To delete it too:  rm -rf ~/.trimtab"
fi
say "Trimtab is uninstalled."
