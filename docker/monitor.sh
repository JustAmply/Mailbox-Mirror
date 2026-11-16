#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/mailbox-mirror/sync-job-state.sh
source /usr/local/lib/mailbox-mirror/notifications.sh

sleep_pid=""
stop() {
  [[ -z "$sleep_pid" ]] || kill "$sleep_pid" 2>/dev/null || true
  exit 0
}
trap stop TERM INT
while true; do
  sync_job_notify
  sleep 30 &
  sleep_pid=$!
  wait "$sleep_pid" || true
  sleep_pid=""
done
