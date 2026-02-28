#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -Iseconds)] $*"
}

cron_schedule="${CRON_SCHEDULE:-*/5 * * * *}"

if [[ -n "${TZ:-}" && -f "/usr/share/zoneinfo/${TZ}" ]]; then
  ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  echo "${TZ}" > /etc/timezone
fi

# Snapshot runtime env so cron jobs can read the same credentials/options.
: > /etc/imapsync.env
while IFS='=' read -r key value; do
  printf 'export %s=%q\n' "$key" "$value" >> /etc/imapsync.env
done < <(printenv)

cat > /etc/cron.d/imapsync <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${cron_schedule} root /usr/local/bin/cron-runner.sh >> /var/log/imapsync.log 2>&1
EOF
chmod 0644 /etc/cron.d/imapsync

touch /var/log/imapsync.log

if [[ "${RUN_ON_STARTUP:-true}" == "true" ]]; then
  log "Running initial imapsync sync..."
  /usr/local/bin/run-imapsync.sh >> /var/log/imapsync.log 2>&1 || log "Initial sync failed; cron retries based on schedule."
fi

log "Starting cron with schedule: ${cron_schedule}"
cron -f &
cron_pid=$!

tail -F /var/log/imapsync.log &
tail_pid=$!

term() {
  log "Stopping container..."
  kill "${cron_pid}" "${tail_pid}" 2>/dev/null || true
}
trap term SIGINT SIGTERM

wait -n "${cron_pid}" "${tail_pid}"