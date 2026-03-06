#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -Iseconds)] $*"
}

require_env() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    log "Missing required env var: ${var_name}"
    exit 1
  fi
}

validate_bool() {
  local var_name="$1"
  local value="${!var_name:-}"

  if [[ -z "$value" ]]; then
    return 0
  fi

  case "$value" in
    true|false) ;;
    *)
      log "Invalid boolean value for ${var_name}: ${value} (expected true or false)"
      exit 1
      ;;
  esac
}

validate_positive_int() {
  local var_name="$1"
  local value="${!var_name:-}"

  if [[ -z "$value" ]]; then
    return 0
  fi

  if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 )); then
    log "Invalid integer value for ${var_name}: ${value} (expected a positive number)"
    exit 1
  fi
}

validate_cron_schedule() {
  local schedule="$1"

  if [[ "$schedule" =~ [[:cntrl:]] ]]; then
    log "Invalid CRON_SCHEDULE: control characters are not allowed"
    exit 1
  fi

  if [[ "$schedule" =~ ^@(reboot|yearly|annually|monthly|weekly|daily|midnight|hourly)$ ]]; then
    return 0
  fi

  read -r -a parts <<< "$schedule"
  if [[ "${#parts[@]}" -ne 5 ]]; then
    log "Invalid CRON_SCHEDULE: ${schedule}"
    log "Expected either a cron macro like @hourly or five cron fields."
    exit 1
  fi
}

cron_schedule="${CRON_SCHEDULE:-*/5 * * * *}"
state_dir="/var/lib/imapsync"

require_env HOST1
require_env USER1
require_env PASSWORD1
require_env HOST2
require_env USER2
require_env PASSWORD2

validate_bool RUN_ON_STARTUP
validate_bool DRY_RUN
validate_bool SSL1
validate_bool SSL2
validate_positive_int MAX_LOG_SIZE_MB
validate_positive_int HEALTHCHECK_MAX_AGE_MINUTES
validate_cron_schedule "$cron_schedule"

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
${cron_schedule} root /usr/local/bin/cron-runner.sh >> /var/log/imapsync.log 2>&1
EOF
chmod 0644 /etc/cron.d/imapsync

touch /var/log/imapsync.log

if [[ "${RUN_ON_STARTUP:-true}" == "true" ]]; then
  log "Running initial imapsync sync..."
  /usr/local/bin/cron-runner.sh >> /var/log/imapsync.log 2>&1 || log "Initial sync failed; cron retries based on schedule."
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
