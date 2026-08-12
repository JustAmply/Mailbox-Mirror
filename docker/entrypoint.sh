#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -Iseconds)] $*"
}

state_dir="/var/lib/imapsync"

source /usr/local/lib/mailbox-mirror/config.sh

mailbox_mirror_config_load
cron_schedule="$CRON_SCHEDULE"

if [[ -n "${TZ:-}" && -f "/usr/share/zoneinfo/${TZ}" ]]; then
  ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  echo "${TZ}" > /etc/timezone
fi

mkdir -p "$state_dir"
date +%s > "${state_dir}/container_started_at"

# Snapshot runtime env so cron jobs can read the same credentials/options.
: > /etc/imapsync.env
while IFS='=' read -r key value; do
  printf 'export %s=%q\n' "$key" "$value" >> /etc/imapsync.env
done < <(printenv)

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
echo "${cron_pid}" > /var/run/mailbox-mirror-cron.pid

tail -F /var/log/imapsync.log &
tail_pid=$!

term() {
  log "Stopping container..."
  kill "${cron_pid}" "${tail_pid}" 2>/dev/null || true
}
trap term SIGINT SIGTERM

wait -n "${cron_pid}" "${tail_pid}"
