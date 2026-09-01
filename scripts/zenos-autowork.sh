#!/usr/bin/env bash
set -uo pipefail

ROOT="/home/doromiert/Projects/zenos-next"
STATE_DIR="$ROOT/.opencode-unattended"
PROMPT_FILE="$ROOT/scripts/zenos-autowork-prompt.md"
LOG_FILE="$STATE_DIR/opencode.log"
STATUS_FILE="$STATE_DIR/runner.status"
COMPLETE_FILE="$STATE_DIR/WORK_COMPLETE"
LOCK_FILE="$STATE_DIR/runner.lock"
PACIFIC_TZ="America/Los_Angeles"

mkdir -p "$STATE_DIR"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  printf 'another zenos-autowork process is already running\n' >&2
  exit 1
fi

deadline_date="${ZENOS_DEADLINE_DATE:-$(TZ="$PACIFIC_TZ" date +%F)}"
deadline_epoch=$(TZ="$PACIFIC_TZ" date -d "$deadline_date 18:00:00" +%s)

notify() {
  local message=$1
  curl -fsS \
    -H "Title: zenos-next unattended" \
    -H "Tags: computer" \
    -d "$message" \
    "https://ntfy.sh/doromiert" >/dev/null 2>&1 || true
}

shutdown_host() {
  local reason=$1
  printf '%s shutdown: %s\n' "$(date --iso-8601=seconds)" "$reason" | tee -a "$STATUS_FILE"
  notify "Stopping unattended work and shutting down: $reason"
  sync
  if ! loginctl poweroff; then
    systemctl poweroff
  fi
  exit 0
}

printf 'deadline=%s (%s)\n' \
  "$(TZ="$PACIFIC_TZ" date -d "@$deadline_epoch" --iso-8601=seconds)" \
  "$PACIFIC_TZ" >"$STATUS_FILE"
notify "Worker started; deadline is $deadline_date 18:00 America/Los_Angeles"

run_number=0
while true; do
  now=$(date +%s)

  if [[ -f "$COMPLETE_FILE" ]]; then
    shutdown_host "implementation marked complete"
  fi

  if (( now >= deadline_epoch )); then
    shutdown_host "18:00 America/Los_Angeles deadline reached"
  fi

  remaining=$((deadline_epoch - now))
  run_number=$((run_number + 1))
  printf '%s run=%d remaining=%ds\n' \
    "$(date --iso-8601=seconds)" "$run_number" "$remaining" | tee -a "$STATUS_FILE"
  notify "Starting OpenCode run $run_number with $remaining seconds remaining"

  prompt=$(<"$PROMPT_FILE")
  timeout --signal=TERM --kill-after=30s "$remaining" \
    opencode run \
      --auto \
      --agent build \
      --model openai/gpt-5.6 \
      --variant max \
      --title "ZenOS unattended implementation" \
      "$prompt" >>"$LOG_FILE" 2>&1
  result=$?

  printf '%s run=%d exit=%d\n' \
    "$(date --iso-8601=seconds)" "$run_number" "$result" | tee -a "$STATUS_FILE"

  if [[ -f "$COMPLETE_FILE" ]]; then
    shutdown_host "implementation marked complete"
  fi

  if (( $(date +%s) >= deadline_epoch )); then
    shutdown_host "18:00 America/Los_Angeles deadline reached"
  fi

  notify "OpenCode run $run_number ended with status $result; restarting in 10 seconds"
  sleep 10
done
