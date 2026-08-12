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
  local temporary="${target}.tmp.$$"

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
  _sync_job_state_write "${sync_job_state_dir}/last_status" "running"
}

sync_job_state_record_mailbox_run_finished() {
  local result="$1"

  case "$result" in
    success)
      _sync_job_state_write "${sync_job_state_dir}/last_success_at" "$(_sync_job_state_now)"
      ;;
    skipped|failure) ;;
    *)
      _sync_job_state_error "Invalid mailbox run result: ${result}"
      return 1
      ;;
  esac

  _sync_job_state_write "${sync_job_state_dir}/last_status" "$result"
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
      success|running|skipped) ;;
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

  if [[ ! -f "${sync_job_state_dir}/last_success_at" ]]; then
    _sync_job_state_error "No successful mailbox run recorded yet"
    return 1
  fi

  local last_success_at
  last_success_at="$(<"${sync_job_state_dir}/last_success_at")"
  if [[ ! "$last_success_at" =~ ^[0-9]+$ ]]; then
    _sync_job_state_error "Invalid mailbox run timestamp: ${last_success_at}"
    return 1
  fi

  local now max_age_seconds
  now="$(_sync_job_state_now)"
  max_age_seconds=$((10#$max_age_minutes * 60))
  if (( 10#$now - 10#$last_success_at > max_age_seconds )); then
    _sync_job_state_error "Last successful mailbox run is older than ${max_age_minutes} minute(s)"
    return 1
  fi
}
