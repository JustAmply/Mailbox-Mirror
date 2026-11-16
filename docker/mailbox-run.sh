#!/usr/bin/env bash

mailbox_run_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${mailbox_run_lib_dir}/config.sh"
source "${mailbox_run_lib_dir}/sync-job-state.sh"
unset mailbox_run_lib_dir

_mailbox_run_log() {
  if declare -F log >/dev/null; then
    log "$*"
  else
    echo "$*"
  fi
}

_mailbox_run_is_dry_run() {
  local dry="${DRY_RUN:-false}" arg
  local -a extra_args=()
  read -r -a extra_args <<< "${IMAPSYNC_EXTRA_ARGS:-}"
  for arg in "${extra_args[@]}"; do
    case "$arg" in
      --dry) dry=true ;;
      --nodry) dry=false ;;
    esac
  done
  [[ "$dry" == true ]]
}

_mailbox_run_build_command() {
  local -n mailbox_run_command_ref="$1"
  mailbox_run_command_ref=(
    imapsync
    --host1 "$HOST1"
    --user1 "$USER1"
    --passfile1 "$mailbox_password_file1"
    --host2 "$HOST2"
    --user2 "$USER2"
    --passfile2 "$mailbox_password_file2"
    --automap
    --syncinternaldates
    --nofoldersizes
  )

  if [[ -n "${PORT1:-}" ]]; then mailbox_run_command_ref+=(--port1 "$PORT1"); fi
  if [[ -n "${PORT2:-}" ]]; then mailbox_run_command_ref+=(--port2 "$PORT2"); fi
  if [[ "${SSL1:-true}" == "true" ]]; then mailbox_run_command_ref+=(--ssl1); fi
  if [[ "${SSL2:-true}" == "true" ]]; then mailbox_run_command_ref+=(--ssl2); fi
  if [[ -n "${AUTHMECH1:-}" ]]; then mailbox_run_command_ref+=(--authmech1 "$AUTHMECH1"); fi
  if [[ -n "${AUTHMECH2:-}" ]]; then mailbox_run_command_ref+=(--authmech2 "$AUTHMECH2"); fi
  if [[ -n "${FOLDER_FILTER:-}" ]]; then mailbox_run_command_ref+=(--folder "$FOLDER_FILTER"); fi
  if [[ -n "${MAXAGE_DAYS:-}" ]]; then mailbox_run_command_ref+=(--maxage "$MAXAGE_DAYS"); fi
  if _mailbox_run_is_dry_run; then mailbox_run_command_ref+=(--dry); fi
  if [[ -n "${IMAPSYNC_EXTRA_ARGS:-}" ]]; then
    local extra_args
    read -r -a extra_args <<< "${IMAPSYNC_EXTRA_ARGS}"
    mailbox_run_command_ref+=("${extra_args[@]}")
  fi
}

mailbox_run_execute() (
  local lock_file="${LOCK_FILE:-/tmp/imapsync.lock}"
  local run_result="failure"
  local credential_dir="" adapter_pid="" lock_wait_pid="" adapter_exit=1
  local state_lock="${sync_job_state_dir}/run.lock"
  mkdir -p "$sync_job_state_dir" || return
  exec 10>"$state_lock" || return
  # One waiter per mailbox: scheduled overlaps must not overwrite the active run.
  if ! flock -n 10; then
    _mailbox_run_log "This mailbox already has an active or waiting run, skipping this cycle."
    return 0
  fi

  _mailbox_run_finish() {
    local messages=""
    if [[ -n "$credential_dir" && -f "${credential_dir}/output" ]]; then
      messages="$(sed -nE 's/^Messages transferred[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "${credential_dir}/output" | tail -n 1)"
    fi
    sync_job_state_record_mailbox_run_finished "$run_result" "$adapter_exit" "$messages"
    [[ -z "$credential_dir" ]] || rm -rf -- "$credential_dir"
  }
  _mailbox_run_stop() {
    trap '' TERM INT
    if [[ -n "$lock_wait_pid" ]]; then
      kill "$lock_wait_pid" 2>/dev/null || true
      wait "$lock_wait_pid" 2>/dev/null || true
    fi
    if [[ -n "$adapter_pid" ]]; then
      kill -TERM -- "-$adapter_pid" 2>/dev/null || true
      local remaining=$((10#${SHUTDOWN_GRACE_SECONDS:-10}))
      while kill -0 -- "-$adapter_pid" 2>/dev/null && (( remaining > 0 )); do
        sleep 1
        remaining=$((remaining - 1))
      done
      kill -KILL -- "-$adapter_pid" 2>/dev/null || true
      wait "$adapter_pid" 2>/dev/null || true
    fi
    adapter_exit=143
    exit 143
  }
  trap _mailbox_run_finish EXIT
  trap _mailbox_run_stop TERM INT

  sync_job_state_record_mailbox_run_started || return
  mailbox_mirror_config_load || return
  mkdir -p "$(dirname "$lock_file")" || return

  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lock_file" || return
    flock -w "${LOCK_WAIT_SECONDS:-0}" 9 &
    lock_wait_pid=$!
    if ! wait "$lock_wait_pid"; then
      _mailbox_run_log "Previous mailbox run still active for lock ${lock_file}, skipping this cycle."
      run_result="skipped"
      adapter_exit=0
      return 0
    fi
    lock_wait_pid=""
  fi

  local cmd
  credential_dir="$(mktemp -d)" || return
  chmod 700 "$credential_dir"
  local mailbox_password_file1="${PASSWORD1_FILE:-${credential_dir}/source}" mailbox_password_file2="${PASSWORD2_FILE:-${credential_dir}/destination}"
  if [[ -z "${PASSWORD1_FILE:-}" ]]; then
    (umask 077; printf '%s\n' "$PASSWORD1" > "$mailbox_password_file1") || return
  fi
  if [[ -z "${PASSWORD2_FILE:-}" ]]; then
    (umask 077; printf '%s\n' "$PASSWORD2" > "$mailbox_password_file2") || return
  fi
  _mailbox_run_build_command cmd

  if _mailbox_run_is_dry_run; then
    _mailbox_run_log "Starting imapsync in dry-run mode..."
  else
    _mailbox_run_log "Starting imapsync..."
  fi

  local -a execution=(bash -c '"$@" 2>&1 | tee "$MAILBOX_RUN_OUTPUT"; exit "${PIPESTATUS[0]}"' bash "${cmd[@]}")
  if [[ -n "${RUN_TIMEOUT_SECONDS:-}" ]]; then
    execution=(timeout --kill-after="${SHUTDOWN_GRACE_SECONDS:-10}s" "${RUN_TIMEOUT_SECONDS}s" "${execution[@]}")
  fi
  MAILBOX_RUN_OUTPUT="${credential_dir}/output" setsid "${execution[@]}" 9>&- 10>&- &
  adapter_pid=$!
  if wait "$adapter_pid"; then
    adapter_exit=0
    run_result="success"
    if _mailbox_run_is_dry_run; then run_result="dry_run"; fi
    _mailbox_run_log "imapsync finished successfully."
    return 0
  else
    adapter_exit=$?
    return "$adapter_exit"
  fi
)
