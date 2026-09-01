#!/usr/bin/env bash
set -uo pipefail

PACIFIC_TZ="America/Los_Angeles"
deadline_date="${ZENOS_DEADLINE_DATE:-$(TZ="$PACIFIC_TZ" date +%F)}"
deadline_epoch=$(TZ="$PACIFIC_TZ" date -d "$deadline_date 18:00:00" +%s)
remaining=$((deadline_epoch - $(date +%s)))

if (( remaining > 0 )); then
  sleep "$remaining"
fi

curl -fsS \
  -H "Title: zenos-next unattended" \
  -H "Priority: high" \
  -H "Tags: warning" \
  -d "Pacific deadline reached; shutting down host" \
  "https://ntfy.sh/doromiert" >/dev/null 2>&1 || true

sync
if ! loginctl poweroff; then
  systemctl poweroff
fi
