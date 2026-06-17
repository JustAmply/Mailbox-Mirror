#!/usr/bin/env bash

mailbox_run_required_vars=(
  HOST1
  USER1
  PASSWORD1
  HOST2
  USER2
  PASSWORD2
)

mailbox_run_error() {
  if declare -F log >/dev/null; then
    log "$*" >&2
  else
    echo "$*" >&2
  fi
}

mailbox_run_require_env() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    mailbox_run_error "Missing required env var: ${var_name}"
    return 1
  fi
}

mailbox_run_validate_bool() {
  local var_name="$1"
  local value="${!var_name:-}"

  if [[ -z "$value" ]]; then
    return 0
  fi

  case "$value" in
    true|false) ;;
    *)
      mailbox_run_error "Invalid boolean value for ${var_name}: ${value} (expected true or false)"
      return 1
      ;;
  esac
}

mailbox_run_validate_env() {
  local var_name

  for var_name in "${mailbox_run_required_vars[@]}"; do
    mailbox_run_require_env "$var_name" || return 1
  done

  mailbox_run_validate_bool DRY_RUN || return 1
  mailbox_run_validate_bool SSL1 || return 1
  mailbox_run_validate_bool SSL2 || return 1
}

mailbox_run_is_dry_run() {
  [[ "${DRY_RUN:-false}" == "true" ]]
}

mailbox_run_build_command() {
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
  if mailbox_run_is_dry_run; then mailbox_run_command_ref+=(--dry); fi
  if [[ -n "${IMAPSYNC_EXTRA_ARGS:-}" ]]; then
    local extra_args
    read -r -a extra_args <<< "${IMAPSYNC_EXTRA_ARGS}"
    mailbox_run_command_ref+=("${extra_args[@]}")
  fi
}
