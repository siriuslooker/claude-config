#!/bin/bash
# Wrap a long background command so the status line can SEE it running.
# (MACHINE-LEVEL — all sessions, all projects.)
#
# WHY THIS EXISTS. A session waiting on a 5-minute build looks completely idle:
# the Bash tool's run_in_background gives no visible signal anywhere. Subagents
# show up in the status bar; background bash tasks do not. This wrapper closes
# that gap by leaving a marker file the status line can read.
#
# ⚠️ WHY IT KEYS ON A PID AND NOT ON FILES. Two obvious cheaper designs were
# measured and BOTH report a live task as dead:
#   1. The statusLine stdin payload carries nothing about background tasks or
#      subagents at all — checked against the documented schema.
#   2. The task output directory is not a liveness signal. A RUNNING Metro
#      process had a .output file whose mtime was 3 HOURS stale, and completed
#      agent outputs are 0 bytes. "Is the file growing?" is therefore noise.
# Same class of error as keying liveness off a process name, which ~/.claude/
# CLAUDE.md already warns about. So the task registers its own PID and the
# status line asks the OS.
#
# Usage — the command is ONE string, like tools/run-notify.ps1:
#   bash ~/.claude/tools/bg-task.sh "Android build" "bash scripts/build.sh"
#
# Transparent by design: stdout/stderr pass through unmodified, this script
# prints nothing of its own, and it exits with the wrapped command's exit code —
# so it can be dropped in anywhere without changing what the caller reads.
#
# ⚠️ HARD-KILL IS HANDLED BY THE READER, NOT BY A DAEMON. If this wrapper is
# SIGKILLed the EXIT trap never runs and the marker is orphaned. That is fine
# and expected: the status line treats a marker whose PID is dead as gone and
# deletes it on the next render. DO NOT "fix" this with a cleanup daemon or a
# reaper — the PID check already is the cleanup, and a daemon would add a
# process whose own liveness nobody can verify.

set -u

LABEL="${1:-background task}"
CMD="${2:-}"

if [ -z "$CMD" ]; then
    echo "usage: bg-task.sh \"<label>\" \"<command string>\"" >&2
    exit 2
fi

BG_DIR="${BG_TASK_DIR:-$HOME/.claude/.bg-tasks}"
mkdir -p "$BG_DIR" 2>/dev/null

STARTED=$(date +%s)
# $$ is this wrapper's own PID and is what the status line polls with kill -0.
# The id pairs it with the start time so a recycled PID cannot collide with a
# marker this same script wrote earlier.
MARKER="$BG_DIR/$$-$STARTED.json"

cleanup() { rm -f "$MARKER" 2>/dev/null; }
# EXIT covers a normal finish AND a failure; INT/TERM cover a Ctrl-C or a kill.
# rm -f is idempotent, so the EXIT trap firing after one of the others is a no-op.
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# jq builds the JSON so a label or command containing quotes/backslashes cannot
# produce a malformed marker that the status line's single jq pass would choke
# on. jq is already a hard dependency of hooks/statusline.sh, which is the only
# consumer; without it we simply run unmarked rather than writing bad JSON.
if command -v jq >/dev/null 2>&1; then
    jq -n --arg label "$LABEL" --arg cmd "${CMD:0:200}" \
          --argjson pid "$$" --argjson started "$STARTED" \
          '{label: $label, pid: $pid, started: $started, cmd: $cmd}' \
          > "$MARKER" 2>/dev/null
fi

# bash -c in a child: the wrapped command cannot alter this script's traps or
# state, and its exit code comes back cleanly.
bash -c "$CMD"
CODE=$?

cleanup
exit "$CODE"
