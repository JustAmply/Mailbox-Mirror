#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -Iseconds)] $*"
}

source /usr/local/lib/mailbox-mirror/config.sh
source /usr/local/lib/mailbox-mirror/sync-job-state.sh

mailbox_mirror_config_load
cron_schedule="$CRON_SCHEDULE"

if [[ -n "${TZ:-}" && -f "/usr/share/zoneinfo/${TZ}" ]]; then
  ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  echo "${TZ}" > /etc/timezone
fi

sync_job_state_record_container_started

# Cron needs the validated configuration, including credentials. Do not copy
# unrelated container secrets, and never expose a partially written snapshot.
umask 077
mailbox_mirror_config_snapshot > /etc/imapsync.env.tmp
chmod 600 /etc/imapsync.env.tmp
mv /etc/imapsync.env.tmp /etc/imapsync.env

cat > /etc/cron.d/imapsync <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${cron_schedule} root /usr/local/bin/cron-runner.sh
EOF
chmod 0644 /etc/cron.d/imapsync

touch /var/log/imapsync.log

cron_pid="" tail_pid="" startup_pid="" shutdown_requested=false
term() {
  trap '' SIGINT SIGTERM
  log "Stopping container..."
  [[ -z "$startup_pid" ]] || kill -TERM -- "-$startup_pid" 2>/dev/null || true
  # Stop scheduling first, then let the active run terminate its process group
  # and record failure before PID 1 exits.
  [[ -z "$cron_pid" ]] || kill "$cron_pid" 2>/dev/null || true
  if [[ -f "${sync_job_state_dir}/active_pid" ]]; then
    active_pid="$(<"${sync_job_state_dir}/active_pid")"
    if [[ "$active_pid" =~ ^[0-9]+$ ]]; then
      kill -TERM "$active_pid" 2>/dev/null || true
      remaining=$(( 10#${SHUTDOWN_GRACE_SECONDS:-10} + 2 ))
      while kill -0 "$active_pid" 2>/dev/null && (( remaining > 0 )); do
        sleep 1
        remaining=$((remaining - 1))
      done
    fi
  fi
  if [[ -n "$startup_pid" ]]; then
    remaining=$((10#${SHUTDOWN_GRACE_SECONDS:-10} + 2))
    while kill -0 -- "-$startup_pid" 2>/dev/null && (( remaining > 0 )); do
      sleep 1
      remaining=$((remaining - 1))
    done
    kill -KILL -- "-$startup_pid" 2>/dev/null || true
  fi
  [[ -z "$tail_pid" ]] || kill "$tail_pid" 2>/dev/null || true
  wait 2>/dev/null || true
  exit 0
}
# Latch early signals until every launched child has a recorded PID.
trap 'shutdown_requested=true' SIGINT SIGTERM

log "Starting cron with schedule: ${cron_schedule}"
cron -f &
cron_pid=$!
sync_job_state_record_cron_started "$cron_pid"
tail -F /var/log/imapsync.log &
tail_pid=$!

if [[ "${RUN_ON_STARTUP:-true}" == "true" ]]; then
  log "Running initial imapsync sync..."
  setsid /usr/local/bin/cron-runner.sh &
  startup_pid=$!
fi
trap term SIGINT SIGTERM
if [[ "$shutdown_requested" == true ]]; then term; fi
if [[ -n "$startup_pid" ]]; then
  wait "$startup_pid" || log "Initial sync failed; cron retries based on schedule."
fi

wait -n "$cron_pid" "$tail_pid" || true
term
