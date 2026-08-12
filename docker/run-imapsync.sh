#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -Iseconds)] $*"
}

source /usr/local/lib/mailbox-mirror/config.sh
source /usr/local/lib/mailbox-mirror/mailbox-run.sh

state_dir="/var/lib/imapsync"
lock_file="${LOCK_FILE:-/tmp/imapsync.lock}"

mkdir -p "$state_dir"
mkdir -p "$(dirname "$lock_file")"

date +%s > "${state_dir}/last_attempt_at"
echo "running" > "${state_dir}/last_status"
run_result="failure"

on_exit() {
  if [[ "$run_result" == "success" ]]; then
    date +%s > "${state_dir}/last_success_at"
    echo "success" > "${state_dir}/last_status"
  elif [[ "$run_result" == "skipped" ]]; then
    echo "skipped" > "${state_dir}/last_status"
  else
    echo "failure" > "${state_dir}/last_status"
  fi
}
trap on_exit EXIT

mailbox_mirror_config_load

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
