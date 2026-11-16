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

if [[ "${RUN_ON_STARTUP:-true}" == "true" ]]; then
  log "Running initial imapsync sync..."
  /usr/local/bin/cron-runner.sh || log "Initial sync failed; cron retries based on schedule."
fi

log "Starting cron with schedule: ${cron_schedule}"
cron -f &
cron_pid=$!
sync_job_state_record_cron_started "$cron_pid"

tail -F /var/log/imapsync.log &
tail_pid=$!

term() {
  log "Stopping container..."
  kill "${cron_pid}" "${tail_pid}" 2>/dev/null || true
}
trap term SIGINT SIGTERM

wait -n "${cron_pid}" "${tail_pid}"
