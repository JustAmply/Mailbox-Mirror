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
  [[ "$DRY_RUN" == "true" ]]
}

_mailbox_run_build_command() {
  local -n mailbox_run_command_ref="$1"
  mailbox_run_command_ref=(
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

  trap 'sync_job_state_record_mailbox_run_finished "$run_result"' EXIT

  sync_job_state_record_mailbox_run_started || return
  mailbox_mirror_config_load || return
  mkdir -p "$(dirname "$lock_file")" || return

  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lock_file" || return
    if ! flock -n 9; then
      _mailbox_run_log "Previous mailbox run still active for lock ${lock_file}, skipping this cycle."
      run_result="skipped"
      return 0
    fi
  fi

  local cmd
  _mailbox_run_build_command cmd

  if _mailbox_run_is_dry_run; then
    _mailbox_run_log "Starting imapsync in dry-run mode..."
  else
    _mailbox_run_log "Starting imapsync..."
  fi

  local adapter_exit
  if "${cmd[@]}"; then
    run_result="success"
    _mailbox_run_log "imapsync finished successfully."
    return 0
  else
    adapter_exit=$?
    return "$adapter_exit"
  fi
)
