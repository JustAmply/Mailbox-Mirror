#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -Iseconds)] $*"
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
      log "Invalid boolean value for ${var_name}: ${value} (expected true or false)" >&2
      exit 1
      ;;
  esac
}

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

required_vars=(HOST1 USER1 PASSWORD1 HOST2 USER2 PASSWORD2)
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    log "Missing required env var: ${var_name}" >&2
    exit 1
  fi
done

validate_bool DRY_RUN
validate_bool SSL1
validate_bool SSL2

if command -v flock >/dev/null 2>&1; then
  exec 9>"$lock_file"
  if ! flock -n 9; then
    log "Previous imapsync run still active for lock ${lock_file}, skipping this cycle."
    run_result="skipped"
    exit 0
  fi
fi

cmd=(
  imapsync
  --host1 "$HOST1"
  --user1 "$USER1"
  --password1 "$PASSWORD1"
  --host2 "$HOST2"
  --user2 "$USER2"
  --password2 "$PASSWORD2"
  --automap
  --syncinternaldates
  --useuid
  --nofoldersizes
)

if [[ -n "${PORT1:-}" ]]; then cmd+=(--port1 "$PORT1"); fi
if [[ -n "${PORT2:-}" ]]; then cmd+=(--port2 "$PORT2"); fi
if [[ "${SSL1:-true}" == "true" ]]; then cmd+=(--ssl1); fi
if [[ "${SSL2:-true}" == "true" ]]; then cmd+=(--ssl2); fi
if [[ -n "${AUTHMECH1:-}" ]]; then cmd+=(--authmech1 "$AUTHMECH1"); fi
if [[ -n "${AUTHMECH2:-}" ]]; then cmd+=(--authmech2 "$AUTHMECH2"); fi
if [[ -n "${FOLDER_FILTER:-}" ]]; then cmd+=(--folder "$FOLDER_FILTER"); fi
if [[ -n "${MAXAGE_DAYS:-}" ]]; then cmd+=(--maxage "$MAXAGE_DAYS"); fi
if [[ "${DRY_RUN:-false}" == "true" ]]; then cmd+=(--dry); fi
if [[ -n "${IMAPSYNC_EXTRA_ARGS:-}" ]]; then
  read -r -a extra_args <<< "${IMAPSYNC_EXTRA_ARGS}"
  cmd+=("${extra_args[@]}")
fi

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  log "Starting imapsync in dry-run mode..."
else
  log "Starting imapsync..."
fi
"${cmd[@]}"
run_result="success"
log "imapsync finished successfully."
