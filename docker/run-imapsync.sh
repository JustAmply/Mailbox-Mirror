#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -Iseconds)] $*"
}

source /usr/local/lib/mailbox-mirror/config.sh
source /usr/local/lib/mailbox-mirror/mailbox-run.sh
source /usr/local/lib/mailbox-mirror/sync-job-state.sh

lock_file="${LOCK_FILE:-/tmp/imapsync.lock}"

mkdir -p "$(dirname "$lock_file")"

run_result="failure"

on_exit() {
  sync_job_state_record_mailbox_run_finished "$run_result"
}
trap on_exit EXIT

mailbox_mirror_config_load
sync_job_state_record_mailbox_run_started

if command -v flock >/dev/null 2>&1; then
  exec 9>"$lock_file"
  if ! flock -n 9; then
    log "Previous imapsync run still active for lock ${lock_file}, skipping this cycle."
    run_result="skipped"
    exit 0
  fi
fi

mailbox_run_build_command cmd

if mailbox_run_is_dry_run; then
  log "Starting imapsync in dry-run mode..."
else
  log "Starting imapsync..."
fi
"${cmd[@]}"
run_result="success"
log "imapsync finished successfully."
