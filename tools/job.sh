#!/usr/bin/env bash
# job.sh — run a long command detached, then poll it in bounded chunks.
#
# Why this exists: the Bash tool caps a single call at 10 minutes, and a clean
# Android build here takes ~13. That cap is per CALL, not per agent turn — so a
# subagent can own a build of any length as long as the wait is bounded and
# resumable. `start` returns immediately; `wait` polls to a budget under the cap
# and can be called again. That makes builds fully agent-ownable, instead of
# forcing the controller to own the waiting.
#
# Liveness is the PID (kill -0) plus the log's own growth — never a process
# name. `pgrep -f <pattern>` matches its own invoking shell and any other
# process carrying the string; a watcher built that way once reported BUILDING
# for thirty minutes after the build had finished.
#
# Usage:
#   job.sh start "<label>" "<command>"      -> prints JOB=<id>
#   job.sh wait  <id> [budget_seconds]      -> polls; prints running|done
#   job.sh status <id>
#   job.sh log   <id> [lines]
#   job.sh stop  <id>
#   job.sh list
#   job.sh clean [days]                     -> remove finished jobs older than N days (default 7)
#
# Exit codes: wait/status exit 0 while running or on success, 1 if the job
# failed. The job's own exit code is in <dir>/exit and printed.

set -uo pipefail

JOBS_ROOT="${JOB_ROOT:-$HOME/.claude/.jobs}"
CAP=540   # default wait budget, comfortably under the 10-minute tool cap

die() { echo "job.sh: $*" >&2; exit 2; }
jobdir() { echo "$JOBS_ROOT/$1"; }

# Sleep without the `sleep` binary: a fifo nobody writes to, read with a timeout.
# The harness blocks foreground `sleep`, and this is portable to WSL and Git Bash.
_delay() {
  local secs="$1" fifo
  fifo="$(mktemp -u)" || { command sleep "$secs" 2>/dev/null; return; }
  if mkfifo "$fifo" 2>/dev/null; then
    exec 9<>"$fifo"; rm -f "$fifo"
    read -t "$secs" -u 9 _ 2>/dev/null
    exec 9>&-
  else
    command sleep "$secs" 2>/dev/null
  fi
  return 0
}

cmd_start() {
  local label="${1:-job}" command="${2:-}"
  [ -n "$command" ] || die "start needs a command"
  local slug id dir
  slug="$(printf '%s' "$label" | tr '[:upper:] ' '[:lower:]-' | tr -cd '[:alnum:]-' | cut -c1-32)"
  id="${slug:-job}-$(date +%Y%m%d-%H%M%S)-$$"
  dir="$(jobdir "$id")"
  mkdir -p "$dir" || die "cannot create $dir"
  printf '%s\n' "$label"   > "$dir/label"
  printf '%s\n' "$command" > "$dir/cmd"
  date +%s                 > "$dir/started"
  : > "$dir/log"
  # Detach so the job survives this tool call. The detached shell records its
  # OWN pid: $! would be the wrapper parent, which exits immediately after
  # forking, so liveness would read as dead at once.
  # ⚠️ `setsid` does NOT exist in Git Bash (MSYS) — only in WSL. Agents run in
  # Git Bash, so nohup is the path that actually gets used here.
  local runner='
    printf "%s\n" "$$" > "$2/pid"
    bash -c "$1" > "$2/log" 2>&1 < /dev/null
    printf "%s\n" "$?" > "$2/exit"
  '
  if command -v setsid >/dev/null 2>&1; then
    setsid bash -c "$runner" _ "$command" "$dir" >/dev/null 2>&1 &
  else
    nohup bash -c "$runner" _ "$command" "$dir" >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
  # Give the detached shell a moment to write its pid before anyone polls it.
  local tries=0
  while [ ! -s "$dir/pid" ] && [ "$tries" -lt 10 ]; do _delay 1; tries=$(( tries + 1 )); done
  echo "JOB=$id"
  echo "dir=$dir"
}

_alive() {
  local dir="$1" pid
  pid="$(cat "$dir/pid" 2>/dev/null || echo)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

_report() {
  local dir="$1" started now elapsed lines ex
  started="$(cat "$dir/started" 2>/dev/null || echo 0)"
  now="$(date +%s)"; elapsed=$(( now - started ))
  lines="$(wc -l < "$dir/log" 2>/dev/null | tr -d ' ' || echo 0)"
  if [ -f "$dir/exit" ]; then
    ex="$(cat "$dir/exit")"
    echo "status=done exit=$ex elapsed=${elapsed}s log_lines=$lines"
    echo "--- last 20 log lines ---"
    tail -20 "$dir/log" 2>/dev/null
    [ "$ex" = "0" ] || return 1
    return 0
  fi
  if _alive "$dir"; then
    echo "status=running elapsed=${elapsed}s log_lines=$lines"
    echo "--- last 5 log lines ---"
    tail -5 "$dir/log" 2>/dev/null
    return 0
  fi
  # No exit file and the PID is gone: killed, or the machine restarted.
  echo "status=vanished elapsed=${elapsed}s log_lines=$lines"
  echo "(no exit file and the pid is not alive — the job was killed, not completed)"
  echo "--- last 20 log lines ---"
  tail -20 "$dir/log" 2>/dev/null
  return 1
}

cmd_wait() {
  local id="${1:-}" budget="${2:-$CAP}" dir waited=0
  [ -n "$id" ] || die "wait needs a job id"
  dir="$(jobdir "$id")"; [ -d "$dir" ] || die "no such job: $id"
  while [ "$waited" -lt "$budget" ]; do
    if [ -f "$dir/exit" ] || ! _alive "$dir"; then break; fi
    _delay 5; waited=$(( waited + 5 ))
  done
  _report "$dir"
}

cmd_status() { local dir; dir="$(jobdir "${1:?status needs an id}")"; [ -d "$dir" ] || die "no such job: $1"; _report "$dir"; }
cmd_log()    { local dir; dir="$(jobdir "${1:?log needs an id}")"; tail -"${2:-100}" "$dir/log"; }
cmd_stop()   {
  local dir pid; dir="$(jobdir "${1:?stop needs an id}")"
  pid="$(cat "$dir/pid" 2>/dev/null || echo)"
  [ -n "$pid" ] && kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
  echo "stop signalled: $1"
}
cmd_list() {
  [ -d "$JOBS_ROOT" ] || { echo "(no jobs)"; return 0; }
  local d id st
  for d in "$JOBS_ROOT"/*/; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    if [ -f "$d/exit" ]; then st="done(exit=$(cat "$d/exit"))"
    elif _alive "$d"; then st="running"
    else st="vanished"; fi
    printf '%-52s %s  %s\n' "$id" "$st" "$(cat "$d/label" 2>/dev/null)"
  done
}
cmd_clean() {
  local days="${1:-7}" d
  [ -d "$JOBS_ROOT" ] || return 0
  for d in "$JOBS_ROOT"/*/; do
    [ -f "$d/exit" ] || continue          # never remove a job still running
    if [ -n "$(find "$d" -maxdepth 0 -mtime +"$days" 2>/dev/null)" ]; then
      rm -rf "$d"; echo "removed $(basename "$d")"
    fi
  done
}

case "${1:-}" in
  start)  shift; cmd_start "$@" ;;
  wait)   shift; cmd_wait  "$@" ;;
  status) shift; cmd_status "$@" ;;
  log)    shift; cmd_log   "$@" ;;
  stop)   shift; cmd_stop  "$@" ;;
  list)   shift; cmd_list  "$@" ;;
  clean)  shift; cmd_clean "$@" ;;
  *) sed -n '2,30p' "$0" >&2; exit 2 ;;
esac
