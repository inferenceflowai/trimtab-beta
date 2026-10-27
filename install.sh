#!/usr/bin/env bash
# Trimtab beta installer.   curl -fsSL https://raw.githubusercontent.com/rayzhao27/trimtab-beta/main/install.sh | bash
#
# Apple Silicon Mac. Installs `uv` if needed, lets uv fetch its OWN Python 3.11 (your conda / venv / system Python
# are never used or touched), creates an isolated environment at ~/.trimtab/app, installs the wheel from the GitHub
# release after checking its SHA256, and links `trimtab` into ~/.local/bin. Running it again upgrades in place.
# Your data in ~/.trimtab (settings, keys, history) is never deleted.
#
# Env: TRIMTAB_VERSION=0.1.0b1   pin a version (default: the latest release)
#      TRIMTAB_WHEEL=/path/x.whl  install a local wheel (offline / testing; SHA256SUMS next to it is checked if present)
#      TRIMTAB_MANIFEST=path|url  use this manifest instead of the release's (testing)
#      TRIMTAB_REPO=owner/repo    override the release repo
set -euo pipefail

GITHUB_REPO="${TRIMTAB_REPO:-rayzhao27/trimtab-beta}"      # <- the one place to change the GitHub owner / repo
PYTHON_MINOR="3.11"
PY_TAG="cp311"
APP_HOME="$HOME/.trimtab"
APP="$APP_HOME/app"
BIN="$HOME/.local/bin"
RELEASES="https://github.com/$GITHUB_REPO/releases"
RC_BEGIN="# >>> trimtab (added by the installer)"
RC_END="# <<< trimtab"

say() { printf '%s\n' "$*"; }
die() { printf '\nError: %s\n' "$*" >&2; exit 1; }
step() { printf '==> %s\n' "$*"; }

# 1. platform
[ "$(uname -s)" = "Darwin" ] || die "this beta runs on macOS (Apple Silicon) only. Linux and Windows are not supported yet."
case "$(uname -m)" in
  arm64) ;;
  x86_64) die "Intel Macs are not supported in this beta yet. It needs an Apple Silicon Mac (M1 or newer)." ;;
  *) die "unsupported CPU: $(uname -m)" ;;
esac
command -v curl >/dev/null 2>&1 || die "curl is missing."
mkdir -p "$APP_HOME" "$BIN"

# 2. uv (its own Python manager; installed only if missing, without touching your shell config)
UV_BY_US=false
UV="$(command -v uv 2>/dev/null || true)"
if [ -z "$UV" ] && [ -x "$BIN/uv" ]; then UV="$BIN/uv"; fi
if [ -z "$UV" ]; then
  step "Installing uv (a small tool that provides Trimtab's own Python)"
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$BIN" UV_NO_MODIFY_PATH=1 INSTALLER_NO_MODIFY_PATH=1 sh >/dev/null 2>&1 \
    || die "couldn't install uv. Check your connection and try again (https://docs.astral.sh/uv/)."
  UV="$BIN/uv"; UV_BY_US=true
  [ -x "$UV" ] || die "uv was not found at $UV after installing it."
fi
# only uv-managed Pythons: never the system, Homebrew or conda ones
export UV_PYTHON_PREFERENCE=only-managed UV_PYTHON_DOWNLOADS=automatic

# 3. Python for the app
step "Getting Python $PYTHON_MINOR (managed by uv, separate from any Python you have)"
"$UV" python install "$PYTHON_MINOR" >/dev/null 2>&1 || die "uv couldn't fetch Python $PYTHON_MINOR. Check your connection and try again."
PY="$("$UV" python find "$PYTHON_MINOR" 2>/dev/null || true)"
[ -x "$PY" ] || die "couldn't locate the uv-managed Python $PYTHON_MINOR."

# 4. which wheel: a local one, or the release's (found through the manifest, not the GitHub API)
WORK="$(mktemp -d "${TMPDIR:-/tmp}/trimtab-install.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
OLD_VERSION=""
[ -x "$APP/bin/trimtab" ] && OLD_VERSION="$("$APP/bin/python" -c 'import trimtab; print(trimtab.__version__)' 2>/dev/null || true)"

fetch() { # url-or-path -> file
  case "$1" in
    http*://*) curl -fsSL --retry 2 "$1" -o "$2" ;;
    *) cp "$1" "$2" ;;
  esac
}
json() { # file key... -> prints the value (python from uv; no jq needed)
  "$PY" - "$@" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    d = d[k]
print(d)
PYEOF
}

MANIFEST_FILE=""
if [ -n "${TRIMTAB_MANIFEST:-}" ]; then
  fetch "$TRIMTAB_MANIFEST" "$WORK/manifest.json" || die "couldn't read the manifest $TRIMTAB_MANIFEST."
  MANIFEST_FILE="$WORK/manifest.json"
elif [ -z "${TRIMTAB_WHEEL:-}" ]; then
  if [ -n "${TRIMTAB_VERSION:-}" ]; then MURL="$RELEASES/download/v${TRIMTAB_VERSION#v}/manifest.json"; else MURL="$RELEASES/latest/download/manifest.json"; fi
  step "Finding the release"
  fetch "$MURL" "$WORK/manifest.json" || die "couldn't download the release manifest ($MURL). Check your connection, or that this version exists."
  MANIFEST_FILE="$WORK/manifest.json"
fi

if [ -n "${TRIMTAB_WHEEL:-}" ]; then
  [ -f "$TRIMTAB_WHEEL" ] || die "TRIMTAB_WHEEL not found: $TRIMTAB_WHEEL"
  WHEEL="$TRIMTAB_WHEEL"
  case "$(basename "$WHEEL")" in *-"$PY_TAG"-"$PY_TAG"-*) ;; *) die "$(basename "$WHEEL") is not a $PY_TAG wheel (this installer uses Python $PYTHON_MINOR)." ;; esac
  EXPECTED=""
  if [ -n "$MANIFEST_FILE" ]; then EXPECTED="$(json "$MANIFEST_FILE" wheels "$PY_TAG" sha256 2>/dev/null || true)"; fi
  if [ -z "$EXPECTED" ] && [ -f "$(dirname "$WHEEL")/SHA256SUMS" ]; then
    EXPECTED="$(grep " $(basename "$WHEEL")\$" "$(dirname "$WHEEL")/SHA256SUMS" | awk '{print $1}' | head -1 || true)"
  fi
  VERSION="$(basename "$WHEEL" | cut -d- -f2)"
else
  VERSION="$(json "$MANIFEST_FILE" version)" || die "the release manifest is unreadable."
  NAME="$(json "$MANIFEST_FILE" wheels "$PY_TAG" file 2>/dev/null || true)"
  [ -n "$NAME" ] || die "release $VERSION has no wheel for Python $PYTHON_MINOR."
  BASE="$RELEASES/download/v$VERSION"
  step "Downloading Trimtab $VERSION"
  curl -fSL --retry 2 --progress-bar "$BASE/$NAME" -o "$WORK/$NAME" || die "couldn't download $BASE/$NAME."
  curl -fsSL --retry 2 "$BASE/SHA256SUMS" -o "$WORK/SHA256SUMS" || die "couldn't download $BASE/SHA256SUMS."
  WHEEL="$WORK/$NAME"
  EXPECTED="$(grep " $NAME\$" "$WORK/SHA256SUMS" | awk '{print $1}' | head -1 || true)"
  [ -n "$EXPECTED" ] || die "$NAME is not listed in SHA256SUMS; refusing to install it."
fi

# 5. verify the SHA256
if [ -n "$EXPECTED" ]; then
  ACTUAL="$(shasum -a 256 "$WHEEL" | awk '{print $1}')"
  [ "$EXPECTED" = "$ACTUAL" ] || die "checksum mismatch for $(basename "$WHEEL"): expected $EXPECTED, got $ACTUAL. Don't use this file; run the installer again."
  say "Checksum OK"
else
  say "Note: no checksum available for this local wheel, skipping the check."
fi

# 6. the isolated environment (replaced on every install; ~/.trimtab data is not touched)
step "Installing into $APP"
"$UV" venv --python "$PY" --clear -q "$APP" || die "couldn't create the environment at $APP."
"$UV" pip install -q --python "$APP/bin/python" "$WHEEL" || die "couldn't install the wheel (see the message above)."

# 7. the command
ln -sfn "$APP/bin/trimtab" "$BIN/trimtab"

# 8. PATH: only if ~/.local/bin isn't on it yet; one marked block, added once
PATH_NOTE=""
case ":$PATH:" in
  *":$BIN:"*) ;;
  *)
    case "$(basename "${SHELL:-/bin/zsh}")" in
      zsh) RC="${ZDOTDIR:-$HOME}/.zshrc" ;;
      bash) RC="$HOME/.bash_profile" ;;
      *) RC="$HOME/.profile" ;;
    esac
    if ! grep -qF "$RC_BEGIN" "$RC" 2>/dev/null; then
      { printf '\n%s\n' "$RC_BEGIN"; printf 'export PATH="$HOME/.local/bin:$PATH"\n'; printf '%s\n' "$RC_END"; } >> "$RC"
    fi
    PATH_NOTE="Open a new terminal window first (or run: source $RC)."
    ;;
esac

# 9. what uninstall needs to know
UV_FLAG="$UV_BY_US"
if [ -f "$APP_HOME/install.json" ] && grep -q '"uv_installed_by_trimtab": true' "$APP_HOME/install.json" 2>/dev/null; then UV_FLAG=true; fi
printf '{"version": "%s", "uv_installed_by_trimtab": %s, "rc_file": "%s", "installed_at": "%s"}\n' \
  "$VERSION" "$UV_FLAG" "${RC:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$APP_HOME/install.json"

say ""
if [ -n "$OLD_VERSION" ] && [ "$OLD_VERSION" != "$VERSION" ]; then say "Upgraded Trimtab $OLD_VERSION -> $VERSION."
elif [ -n "$OLD_VERSION" ]; then say "Reinstalled Trimtab $VERSION."
else say "Installed Trimtab $VERSION."; fi
[ -n "$PATH_NOTE" ] && say "$PATH_NOTE"
say "Run: trimtab"
