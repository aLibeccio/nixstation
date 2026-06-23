#!/usr/bin/env bash
# codex-guarded.sh — run `codex exec` so it can NEVER silently hang.
#
# Why: `codex exec` is a thin client to the local Codex.app app-server + a remote
# model. When that round-trip stalls it produces no output and has no client-side
# timeout, so a naive caller waits forever. This wrapper adds a hard cap + an idle
# watchdog (kill if no new output for IDLE secs) and streams to a logfile (no
# tail-pipe buffering). It exits non-zero on kill so the caller AUTO-FALLS-BACK
# to a non-codex implementer instead of waiting.
#
# Portable on macOS (no GNU `timeout`/`gtimeout` dependency — watchdog in bash).
#
# Usage:
#   codex-guarded.sh <hard_secs> <idle_secs> -C <repo> "<prompt>"
# Example:
#   ~/.claude/codex-guarded.sh 420 60 -C /path/to/repo "implement Task N ..."
#
# Exit codes: codex's own rc on completion; 124 if killed (hard cap or idle stall).
set -uo pipefail

HARD="${1:?usage: codex-guarded.sh <hard_secs> <idle_secs> -C <repo> \"<prompt>\"}"; shift
IDLE="${1:?usage: codex-guarded.sh <hard_secs> <idle_secs> -C <repo> \"<prompt>\"}"; shift

LOG="$(mktemp -t codexg.XXXXXX.log)"
echo "[codex-guarded] log=$LOG hard=${HARD}s idle=${IDLE}s" >&2

# --dangerously-bypass-approvals-and-sandbox is required for non-interactive use.
# NOTE: there is no supported per-call way to disable codex's plugin SessionStart
# hooks (no `codex plugin disable`; `-c plugins."x".enabled=false` does not take
# effect; `--ignore-user-config` would also drop the model/reasoning pin). The
# hooks run on every exec but normally finish in seconds — the real safety net for
# a genuine stall is the hard-cap + idle-watchdog below, which kills + signals the
# caller to fall back. To truly remove the hooks, set enabled=false in
# ~/.codex/config.toml (also affects interactive Codex.app).
# evidence-discipline: EVIDENCE_NO_BLOCK=1 → the Stop hook runs warn-only here, so a
#   block-driven auto-continue can't push this guarded run past the hard cap.
# --dangerously-bypass-hook-trust → let HM-injected (not-yet-trusted) hooks run AFK
#   (interactive Codex still prompts to trust once).
EVIDENCE_NO_BLOCK=1 codex exec --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust "$@" >"$LOG" 2>&1 &
PID=$!

start=$(date +%s); last_size=-1; last_change=$start; reason=""
while kill -0 "$PID" 2>/dev/null; do
  sleep 5
  now=$(date +%s)
  cur_size=$(wc -c <"$LOG" 2>/dev/null || echo 0)
  if [ "$cur_size" != "$last_size" ]; then last_size="$cur_size"; last_change="$now"; fi
  if [ $((now - start)) -ge "$HARD" ]; then reason="hard cap ${HARD}s"; break; fi
  if [ $((now - last_change)) -ge "$IDLE" ]; then reason="idle stall ${IDLE}s (no output)"; break; fi
done

if kill -0 "$PID" 2>/dev/null; then
  echo "[codex-guarded] KILLING pid=$PID — $reason" >&2
  pkill -KILL -P "$PID" 2>/dev/null || true
  kill -KILL "$PID" 2>/dev/null || true
  cat "$LOG"
  exit 124
fi

wait "$PID"; rc=$?
cat "$LOG"
exit "$rc"
