#!/usr/bin/env bash
set -euo pipefail

state_dir="/var/lib/imapsync"
pid_file="/var/run/mailbox-mirror-cron.pid"
max_age_minutes="${HEALTHCHECK_MAX_AGE_MINUTES:-}"

if [[ ! -f "$pid_file" ]]; then
  echo "Missing cron pid file: ${pid_file}" >&2
  exit 1
fi

cron_pid="$(<"$pid_file")"
if ! kill -0 "$cron_pid" 2>/dev/null; then
  echo "Cron process is not running: ${cron_pid}" >&2
  exit 1
fi

if [[ -f "${state_dir}/last_status" ]]; then
  last_status="$(<"${state_dir}/last_status")"
  if [[ "$last_status" == "failure" ]]; then
    echo "Last imapsync run failed" >&2
    exit 1
  fi
fi

if [[ -n "$max_age_minutes" ]]; then
  if [[ ! "$max_age_minutes" =~ ^[0-9]+$ ]] || (( max_age_minutes < 1 )); then
    echo "Invalid HEALTHCHECK_MAX_AGE_MINUTES: ${max_age_minutes}" >&2
    exit 1
  fi

  if [[ ! -f "${state_dir}/last_success_at" ]]; then
    echo "No successful imapsync run recorded yet" >&2
    exit 1
  fi

  now="$(date +%s)"
  last_success_at="$(<"${state_dir}/last_success_at")"
  max_age_seconds=$((max_age_minutes * 60))

  if (( now - last_success_at > max_age_seconds )); then
    echo "Last successful imapsync run is older than ${max_age_minutes} minute(s)" >&2
    exit 1
  fi
fi
