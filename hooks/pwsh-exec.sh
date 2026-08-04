#!/usr/bin/env bash
# Resolves a PowerShell 7 interpreter, then runs a .ps1 with it.
#
# Why this exists: the hooks used to invoke `pwsh` by name. On a machine where
# PowerShell 7 came from the Microsoft Store, the only thing on PATH is an alias
# in %LOCALAPPDATA%\Microsoft\WindowsApps — a single User-PATH entry. Repairing
# PATH by hand after a crash on 2026-08-04 dropped that entry, so every
# `pwsh` hook died with exit 127 and the idle notifications stopped, SILENTLY:
# nobody notices a notifier that fails to fire. Resolving the interpreter here
# means a PATH mishap can no longer take the hooks down.
#
# Kept as a bash launcher rather than a hardcoded path because the profile is
# shared across machines (see CLAUDE.md) and pwsh lives somewhere different for
# a Store install, an MSI install and a Linux/macOS host.
#
# Usage: pwsh-exec.sh <script.ps1> [args...]

set -euo pipefail

resolve_pwsh() {
  # An inherited PATH is the fast path and the right answer when it works.
  if command -v pwsh >/dev/null 2>&1; then
    command -v pwsh
    return 0
  fi

  local candidates=() c localappdata
  if [ -n "${LOCALAPPDATA:-}" ]; then
    localappdata="$LOCALAPPDATA"
    # LOCALAPPDATA arrives as a Windows path; mixed separators are a coin flip.
    if command -v cygpath >/dev/null 2>&1; then
      localappdata="$(cygpath -u "$LOCALAPPDATA")"
    fi
    candidates+=("$localappdata/Microsoft/WindowsApps/pwsh.exe")
  fi
  candidates+=(
    "/c/Program Files/PowerShell/7/pwsh.exe"
    "/c/Program Files/PowerShell/7-preview/pwsh.exe"
    "/opt/microsoft/powershell/7/pwsh"
    "/usr/local/bin/pwsh"
    "/usr/bin/pwsh"
  )

  for c in "${candidates[@]}"; do
    if [ -x "$c" ]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

if [ "$#" -lt 1 ]; then
  echo "pwsh-exec: no script given" >&2
  exit 0
fi

# Deliberately exit 0 on failure. These hooks drive notifications, and a
# UserPromptSubmit hook that exits non-zero can block the prompt — a broken
# notifier must never cost the session a turn. stderr still surfaces as a hook
# warning, so this fails LOUDLY-but-harmlessly rather than the silent 127 above.
if ! PWSH="$(resolve_pwsh)"; then
  echo "pwsh-exec: no PowerShell 7 interpreter found; skipped $1" >&2
  exit 0
fi

exec "$PWSH" -NoProfile -File "$@"
