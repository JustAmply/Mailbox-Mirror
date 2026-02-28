#!/usr/bin/env bash
set -euo pipefail

required_vars=(HOST1 USER1 PASSWORD1 HOST2 USER2 PASSWORD2)
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "[$(date -Iseconds)] Missing required env var: ${var_name}" >&2
    exit 1
  fi
done

if command -v flock >/dev/null 2>&1; then
  exec 9>/tmp/imapsync.lock
  if ! flock -n 9; then
    echo "[$(date -Iseconds)] Previous imapsync run still active, skipping this cycle."
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
if [[ -n "${IMAPSYNC_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra_args=( ${IMAPSYNC_EXTRA_ARGS} )
  cmd+=("${extra_args[@]}")
fi

echo "[$(date -Iseconds)] Starting imapsync..."
"${cmd[@]}"
echo "[$(date -Iseconds)] imapsync finished successfully."