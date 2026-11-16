#!/usr/bin/env bash

_sync_job_notify() (
  [[ -n "${WEBHOOK_URL:-}" ]] || return 0
  mkdir -p "$sync_job_state_dir" || return
  exec 8>"${sync_job_state_dir}/notify.lock" || return
  flock -n 8 || return 0

  local status=unknown failures=0 now reason="" active="" event timestamp success_file
  now="$(_sync_job_state_now)"
  if [[ -f "${sync_job_state_dir}/last_status" ]]; then
    status="$(<"${sync_job_state_dir}/last_status")"
  fi
  if [[ -f "${sync_job_state_dir}/consecutive_failures" ]]; then
    failures="$(<"${sync_job_state_dir}/consecutive_failures")"
  fi
  if [[ "$status" == running && -n "${HEALTHCHECK_MAX_RUN_MINUTES:-}" && -f "${sync_job_state_dir}/last_attempt_at" ]]; then
    timestamp="$(<"${sync_job_state_dir}/last_attempt_at")"
    if (( now - timestamp > 10#$HEALTHCHECK_MAX_RUN_MINUTES * 60 )); then
      reason=run_timeout
    fi
  fi
  if [[ -z "$reason" ]] && (( failures >= 10#${WEBHOOK_FAILURE_THRESHOLD:-3} )); then
    reason=failure
  fi
  if [[ -z "$reason" && -n "${HEALTHCHECK_MAX_AGE_MINUTES:-}" ]]; then
    success_file="${sync_job_state_dir}/last_success_at"
    if sync_job_state_is_dry_run; then
      success_file="${sync_job_state_dir}/last_dry_run_at"
    fi
    timestamp=0
    if [[ -f "$success_file" ]]; then
      timestamp="$(<"$success_file")"
    elif [[ -f "${sync_job_state_dir}/container_started_at" ]]; then
      timestamp="$(<"${sync_job_state_dir}/container_started_at")"
    fi
    if (( now - timestamp > 10#$HEALTHCHECK_MAX_AGE_MINUTES * 60 )); then
      reason=stale
    fi
  fi

  if [[ -f "${sync_job_state_dir}/notification_active" ]]; then
    active="$(<"${sync_job_state_dir}/notification_active")"
  fi
  if [[ -n "$reason" ]]; then
    [[ -z "$active" ]] || return 0
    event=alert
  elif [[ -n "$active" && ( "$status" == success || "$status" == dry_run ) ]]; then
    event=recovery
    reason="$active"
  else
    return 0
  fi

  local payload
  payload="$(perl -MJSON::PP -e '
    use strict;
    use warnings;
    my ($event, $reason, $directory) = @ARGV;
    my %payload = (event => $event, reason => $reason);
    for my $field (qw(last_status last_exit_code consecutive_failures consecutive_skips
        last_success_at last_dry_run_at last_duration_seconds last_messages_transferred)) {
      my $value;
      if (open my $file, "<", "$directory/$field") {
        $value = <$file>;
        close $file;
        chomp $value if defined $value;
      }
      if ($field ne "last_status") {
        $value = defined($value) && $value =~ /^\d+$/ ? 0 + $value : undef;
      }
      $payload{$field} = $value;
    }
    print JSON::PP->new->canonical->encode(\%payload);
  ' "$event" "$reason" "$sync_job_state_dir")" || return

  # A failed delivery is retried by the next monitor cycle. Never emit URL or response data.
  curl --silent --fail --connect-timeout 5 --max-time 10 --proto '=http,https' \
    --request POST --header 'Content-Type: application/json' \
    --data-binary "$payload" --output /dev/null --url "$WEBHOOK_URL" >/dev/null 2>&1 || return

  if [[ "$event" == alert ]]; then
    _sync_job_state_write "${sync_job_state_dir}/notification_active" "$reason" || return
  else
    rm -f "${sync_job_state_dir}/notification_active" || return
  fi
)

sync_job_notify() {
  if ! _sync_job_notify; then
    echo "Webhook notification could not be delivered; a later check will retry." >&2
  fi
  # Notification delivery must never change the outcome of a Mailbox Run.
  return 0
}
