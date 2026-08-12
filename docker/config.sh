#!/usr/bin/env bash

mailbox_mirror_config_error() {
  if declare -F log >/dev/null; then
    log "$*" >&2
  else
    echo "$*" >&2
  fi
}

mailbox_mirror_config_require() {
  local var_name="$1"

  if [[ -z "${!var_name:-}" ]]; then
    mailbox_mirror_config_error "Missing required env var: ${var_name}"
    return 1
  fi
}

mailbox_mirror_config_validate_bool() {
  local var_name="$1"
  local value="${!var_name:-}"

  case "$value" in
    true|false) ;;
    *)
      mailbox_mirror_config_error "Invalid boolean value for ${var_name}: ${value} (expected true or false)"
      return 1
      ;;
  esac
}

mailbox_mirror_config_validate_positive_int() {
  local var_name="$1"
  local value="${!var_name:-}"

  if [[ -n "$value" ]] && { [[ ! "$value" =~ ^[0-9]+$ ]] || (( 10#$value < 1 )); }; then
    mailbox_mirror_config_error "Invalid integer value for ${var_name}: ${value} (expected a positive number)"
    return 1
  fi
}

mailbox_mirror_config_validate_port() {
  local var_name="$1"
  local value="${!var_name:-}"

  if [[ -n "$value" ]] && { [[ ! "$value" =~ ^[0-9]+$ ]] || (( 10#$value < 1 || 10#$value > 65535 )); }; then
    mailbox_mirror_config_error "Invalid port value for ${var_name}: ${value} (expected 1 to 65535)"
    return 1
  fi
}

mailbox_mirror_config_validate_cron_schedule() {
  local schedule="$CRON_SCHEDULE"

  if [[ "$schedule" =~ [[:cntrl:]] ]]; then
    mailbox_mirror_config_error "Invalid CRON_SCHEDULE: control characters are not allowed"
    return 1
  fi

  if [[ "$schedule" =~ ^@(reboot|yearly|annually|monthly|weekly|daily|midnight|hourly)$ ]]; then
    return 0
  fi

  local parts
  read -r -a parts <<< "$schedule"
  if [[ "${#parts[@]}" -ne 5 ]]; then
    mailbox_mirror_config_error "Invalid CRON_SCHEDULE: ${schedule}"
    mailbox_mirror_config_error "Expected either a cron macro like @hourly or five cron fields."
    return 1
  fi
}

mailbox_mirror_config_load() {
  export CRON_SCHEDULE="${CRON_SCHEDULE:-*/5 * * * *}"
  export RUN_ON_STARTUP="${RUN_ON_STARTUP:-true}"
  export DRY_RUN="${DRY_RUN:-false}"
  export SSL1="${SSL1:-true}"
  export SSL2="${SSL2:-true}"
  export MAX_LOG_SIZE_MB="${MAX_LOG_SIZE_MB:-10}"

  local var_name
  for var_name in HOST1 USER1 PASSWORD1 HOST2 USER2 PASSWORD2; do
    mailbox_mirror_config_require "$var_name" || return 1
  done

  for var_name in RUN_ON_STARTUP DRY_RUN SSL1 SSL2; do
    mailbox_mirror_config_validate_bool "$var_name" || return 1
  done

  mailbox_mirror_config_validate_port PORT1 || return 1
  mailbox_mirror_config_validate_port PORT2 || return 1
  mailbox_mirror_config_validate_positive_int MAXAGE_DAYS || return 1
  mailbox_mirror_config_validate_positive_int MAX_LOG_SIZE_MB || return 1
  mailbox_mirror_config_validate_positive_int HEALTHCHECK_MAX_AGE_MINUTES || return 1
  mailbox_mirror_config_validate_cron_schedule
}
