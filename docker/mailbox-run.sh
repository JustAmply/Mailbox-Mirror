#!/usr/bin/env bash

mailbox_run_is_dry_run() {
  [[ "$DRY_RUN" == "true" ]]
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
