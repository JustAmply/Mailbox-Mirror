#!/usr/bin/env bash

sync_job_state_dir="${SYNC_JOB_STATE_DIR:-/var/lib/imapsync}"
sync_job_state_cron_pid_file="${SYNC_JOB_STATE_CRON_PID_FILE:-/var/run/mailbox-mirror-cron.pid}"

_sync_job_state_error() {
  echo "$*" >&2
}

_sync_job_state_now() {
  date +%s
}

_sync_job_state_write() {
  local target="$1"
  local value="$2"
  local temporary="${target}.tmp.${BASHPID}"

  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$value" > "$temporary"
  mv -f "$temporary" "$target"
}

sync_job_state_record_container_started() {
  _sync_job_state_write "${sync_job_state_dir}/container_started_at" "$(_sync_job_state_now)"
}

sync_job_state_record_cron_started() {
  local cron_pid="$1"

  _sync_job_state_write "$sync_job_state_cron_pid_file" "$cron_pid"
}

sync_job_state_record_mailbox_run_started() {
  _sync_job_state_write "${sync_job_state_dir}/last_attempt_at" "$(_sync_job_state_now)"
  _sync_job_state_write "${sync_job_state_dir}/active_pid" "$BASHPID"
  _sync_job_state_write "${sync_job_state_dir}/last_status" "running"
}

sync_job_state_record_mailbox_run_finished() {
  local result="$1"
  local exit_code="${2:-0}" messages="${3:-${MAILBOX_RUN_MESSAGES_TRANSFERRED:-}}"
  local now started_at failures=0 skips=0
  now="$(_sync_job_state_now)"

  if [[ -f "${sync_job_state_dir}/consecutive_failures" ]]; then
    failures="$(<"${sync_job_state_dir}/consecutive_failures")"
  fi
  if [[ -f "${sync_job_state_dir}/consecutive_skips" ]]; then
    skips="$(<"${sync_job_state_dir}/consecutive_skips")"
  fi

  case "$result" in
    success)
      _sync_job_state_write "${sync_job_state_dir}/last_success_at" "$now"
      failures=0
      skips=0
      ;;
    dry_run)
      _sync_job_state_write "${sync_job_state_dir}/last_dry_run_at" "$now"
      failures=0
      skips=0
      ;;
    skipped)
      skips=$((skips + 1))
      ;;
    failure)
      exit_code="${2:-1}"
      failures=$((failures + 1))
      skips=0
      ;;
    *)
      _sync_job_state_error "Invalid mailbox run result: ${result}"
      return 1
      ;;
  esac

  _sync_job_state_write "${sync_job_state_dir}/last_finished_at" "$now"
  _sync_job_state_write "${sync_job_state_dir}/last_exit_code" "$exit_code"
  _sync_job_state_write "${sync_job_state_dir}/consecutive_failures" "$failures"
  _sync_job_state_write "${sync_job_state_dir}/consecutive_skips" "$skips"
  if [[ -f "${sync_job_state_dir}/last_attempt_at" ]]; then
    started_at="$(<"${sync_job_state_dir}/last_attempt_at")"
    _sync_job_state_write "${sync_job_state_dir}/last_duration_seconds" "$((now - started_at))"
  fi
  if [[ "$messages" =~ ^[0-9]+$ ]]; then
    _sync_job_state_write "${sync_job_state_dir}/last_messages_transferred" "$messages"
  else
    rm -f "${sync_job_state_dir}/last_messages_transferred"
  fi
  _sync_job_state_write "${sync_job_state_dir}/last_status" "$result"
  rm -f "${sync_job_state_dir}/active_pid"
}

sync_job_state_check_health() {
  if [[ ! -f "$sync_job_state_cron_pid_file" ]]; then
    _sync_job_state_error "Missing cron pid file: ${sync_job_state_cron_pid_file}"
    return 1
  fi

  local cron_pid
  cron_pid="$(<"$sync_job_state_cron_pid_file")"
  if [[ ! "$cron_pid" =~ ^[0-9]+$ ]]; then
    _sync_job_state_error "Invalid cron pid: ${cron_pid}"
    return 1
  fi
  if ! kill -0 "$cron_pid" 2>/dev/null; then
    _sync_job_state_error "Cron process is not running: ${cron_pid}"
    return 1
  fi

  if [[ -f "${sync_job_state_dir}/last_status" ]]; then
    local last_status
    last_status="$(<"${sync_job_state_dir}/last_status")"
    case "$last_status" in
      success|dry_run|skipped) ;;
      running)
        if [[ -f "${sync_job_state_dir}/active_pid" ]]; then
          local active_pid
          active_pid="$(<"${sync_job_state_dir}/active_pid")"
          if [[ ! "$active_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$active_pid" 2>/dev/null; then
            _sync_job_state_error "Active mailbox run process is not running"
            return 1
          fi
        fi
        if [[ -n "${HEALTHCHECK_MAX_RUN_MINUTES:-}" && -f "${sync_job_state_dir}/last_attempt_at" ]]; then
          local started_at
          started_at="$(<"${sync_job_state_dir}/last_attempt_at")"
          if [[ ! "$started_at" =~ ^[0-9]+$ ]]; then
            _sync_job_state_error "Invalid mailbox run timestamp: ${started_at}"
            return 1
          fi
          if (( $(_sync_job_state_now) - 10#$started_at > 10#$HEALTHCHECK_MAX_RUN_MINUTES * 60 )); then
            _sync_job_state_error "Active mailbox run is older than ${HEALTHCHECK_MAX_RUN_MINUTES} minute(s)"
            return 1
          fi
        fi
        ;;
      failure)
        _sync_job_state_error "Last mailbox run failed"
        return 1
        ;;
      *)
        _sync_job_state_error "Invalid mailbox run status: ${last_status}"
        return 1
        ;;
    esac
  fi

  local max_age_minutes="${HEALTHCHECK_MAX_AGE_MINUTES:-}"
  if [[ -z "$max_age_minutes" ]]; then
    return 0
  fi

  local success_file="${sync_job_state_dir}/last_success_at" success_description="mailbox run"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    success_file="${sync_job_state_dir}/last_dry_run_at"
    success_description="dry run"
  fi
  local last_success_at now max_age_seconds
  now="$(_sync_job_state_now)"
  max_age_seconds=$((10#$max_age_minutes * 60))
  if [[ ! -f "$success_file" ]]; then
    # Give a newly started container one freshness interval to complete its first run.
    if [[ -f "${sync_job_state_dir}/container_started_at" ]]; then
      last_success_at="$(<"${sync_job_state_dir}/container_started_at")"
      if [[ "$last_success_at" =~ ^[0-9]+$ ]] && (( now - 10#$last_success_at <= max_age_seconds )); then
        return 0
      fi
    fi
    _sync_job_state_error "No successful ${success_description} recorded yet"
    return 1
  fi
  last_success_at="$(<"$success_file")"
  if [[ ! "$last_success_at" =~ ^[0-9]+$ ]]; then
    _sync_job_state_error "Invalid mailbox run timestamp: ${last_success_at}"
    return 1
  fi

  if (( 10#$now - 10#$last_success_at > max_age_seconds )); then
    _sync_job_state_error "Last successful ${success_description} is older than ${max_age_minutes} minute(s)"
    return 1
  fi
}
