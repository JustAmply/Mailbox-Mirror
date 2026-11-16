#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/folder-options.sh"

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

mailbox_mirror_config_snapshot() {
  local key
  while IFS= read -r key; do
    case "$key" in
      HOST[12]|PORT[12]|USER[12]|PASSWORD[12]|PASSWORD[12]_FILE|SSL[12]|AUTHMECH[12]|IMAPSYNC_*|FOLDER_*|DESTINATION_PREFIX|SYNC_MODE|ALLOW_DELETIONS|CRON_SCHEDULE|RUN_ON_STARTUP|DRY_RUN|LOCK_FILE|LOCK_WAIT_SECONDS|MAXAGE_DAYS|HEALTHCHECK_*|MAX_LOG_SIZE_MB|RUN_TIMEOUT_SECONDS|SHUTDOWN_GRACE_SECONDS|WEBHOOK_URL|WEBHOOK_FAILURE_THRESHOLD|SYNC_JOB_STATE_DIR|SYNC_JOB_STATE_CRON_PID_FILE|TZ|PATH|HOME|TMPDIR)
        if [[ "$key" == PASSWORD1 && -n "${PASSWORD1_FILE:-}" ]] || [[ "$key" == PASSWORD2 && -n "${PASSWORD2_FILE:-}" ]]; then continue; fi
        printf 'export %s=%q\n' "$key" "${!key}"
        ;;
    esac
  done < <(compgen -e)
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

_mailbox_mirror_cron_value() {
  local value="${1,,}" minimum="$2" maximum="$3" names="$4"
  local name index="$minimum"

  if [[ "$value" =~ ^[0-9]+$ ]]; then
    value="${value#"${value%%[!0]*}"}"
    value="${value:-0}"
    [[ "${#value}" -le 2 ]] || return 1
    (( value >= minimum && value <= maximum )) || return 1
    printf '%s\n' "$value"
    return 0
  fi

  for name in $names; do
    if [[ "$value" == "$name" ]]; then
      printf '%s\n' "$index"
      return 0
    fi
    index=$((index + 1))
  done
  return 1
}

_mailbox_mirror_validate_cron_field() {
  local field="$1" minimum="$2" maximum="$3" names="$4"
  local item range step start end
  local -a items

  [[ "$field" != ,* && "$field" != *, && "$field" != *,,* ]] || return 1
  IFS=, read -r -a items <<< "$field"
  for item in "${items[@]}"; do
    range="$item"
    if [[ "$item" == */* ]]; then
      range="${item%%/*}"
      step="${item#*/}"
      [[ "$step" =~ ^[0-9]+$ ]] || return 1
      step="${step#"${step%%[!0]*}"}"
      [[ -n "$step" && "${#step}" -le 10 ]] || return 1
      (( step <= 2147483647 )) || return 1
      # Debian cron permits steps on wildcards and ranges, not single values.
      [[ "$range" == '*' || "$range" == *-* ]] || return 1
    fi
    if [[ "$range" == '*' ]]; then
      continue
    elif [[ "$range" == *-* ]]; then
      start="$(_mailbox_mirror_cron_value "${range%%-*}" "$minimum" "$maximum" "$names")" || return 1
      end="$(_mailbox_mirror_cron_value "${range#*-}" "$minimum" "$maximum" "$names")" || return 1
      (( start <= end )) || return 1
    else
      _mailbox_mirror_cron_value "$range" "$minimum" "$maximum" "$names" >/dev/null || return 1
    fi
  done
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

  local -a minimums=(0 0 1 1 0) maximums=(59 23 31 12 7)
  local -a names=('' '' '' 'jan feb mar apr may jun jul aug sep oct nov dec' 'sun mon tue wed thu fri sat')
  local index
  for index in "${!parts[@]}"; do
    if ! _mailbox_mirror_validate_cron_field "${parts[index]}" "${minimums[index]}" "${maximums[index]}" "${names[index]}"; then
      mailbox_mirror_config_error "Invalid CRON_SCHEDULE field $((index + 1)): ${parts[index]}"
      return 1
    fi
  done
}

mailbox_mirror_config_load() {
  export CRON_SCHEDULE="${CRON_SCHEDULE:-*/5 * * * *}"
  export RUN_ON_STARTUP="${RUN_ON_STARTUP:-true}"
  export DRY_RUN="${DRY_RUN:-false}"
  export SSL1="${SSL1:-true}"
  export SSL2="${SSL2:-true}"
  export MAX_LOG_SIZE_MB="${MAX_LOG_SIZE_MB:-10}"

  local var_name
  for var_name in HOST1 USER1 HOST2 USER2; do
    mailbox_mirror_config_require "$var_name" || return 1
  done
  for var_name in PASSWORD1 PASSWORD2; do
    local file_var="${var_name}_FILE"
    if [[ -n "${!file_var:-}" ]]; then
      if [[ ! -r "${!file_var}" || ! -s "${!file_var}" ]]; then
        mailbox_mirror_config_error "${file_var} must reference a readable, nonempty file"
        return 1
      fi
    else
      mailbox_mirror_config_require "$var_name" || return 1
    fi
  done

  for var_name in RUN_ON_STARTUP DRY_RUN SSL1 SSL2; do
    mailbox_mirror_config_validate_bool "$var_name" || return 1
  done

  mailbox_mirror_config_validate_port PORT1 || return 1
  mailbox_mirror_config_validate_port PORT2 || return 1
  mailbox_mirror_config_validate_positive_int MAXAGE_DAYS || return 1
  mailbox_mirror_config_validate_positive_int MAX_LOG_SIZE_MB || return 1
  mailbox_mirror_config_validate_positive_int HEALTHCHECK_MAX_AGE_MINUTES || return 1
  for var_name in HEALTHCHECK_MAX_RUN_MINUTES RUN_TIMEOUT_SECONDS SHUTDOWN_GRACE_SECONDS WEBHOOK_FAILURE_THRESHOLD; do
    mailbox_mirror_config_validate_positive_int "$var_name" || return 1
  done
  if [[ -n "${LOCK_WAIT_SECONDS:-}" && ! "$LOCK_WAIT_SECONDS" =~ ^[0-9]+$ ]]; then
    mailbox_mirror_config_error "LOCK_WAIT_SECONDS must be a nonnegative integer"
    return 1
  fi
  if [[ -n "${WEBHOOK_URL:-}" && ! "$WEBHOOK_URL" =~ ^https?://[^[:space:]]+$ ]]; then
    mailbox_mirror_config_error "WEBHOOK_URL must be an HTTP(S) URL without whitespace"
    return 1
  fi
  mailbox_folder_options_validate || return 1
  mailbox_mirror_config_validate_cron_schedule
}
