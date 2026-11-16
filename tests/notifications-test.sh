#!/usr/bin/env bash
set -euo pipefail

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_JOB_STATE_DIR="${fixture_dir}/state"
source "${repo_root}/docker/sync-job-state.sh"
source "${repo_root}/docker/notifications.sh"

fail() { echo "not ok - $*" >&2; exit 1; }
assert_calls() {
  local count=0
  if [[ -f "$FAKE_CURL_LOG" ]]; then count="$(wc -l < "$FAKE_CURL_LOG")"; fi
  [[ "$count" -eq "$1" ]] || fail "expected $1 webhook calls, got $count"
}
assert_event() {
  tail -n 1 "$FAKE_CURL_LOG" | perl -MJSON::PP -e '
    my ($event, $reason) = @ARGV;
    my $payload = decode_json(<STDIN>);
    die "incorrect event" unless $payload->{event} eq $event && $payload->{reason} eq $reason;
    die "credentials leaked" if exists($payload->{PASSWORD1}) || exists($payload->{WEBHOOK_URL});
  ' "$1" "$2"
}

mkdir -p "${fixture_dir}/bin"
cat > "${fixture_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == --data-binary ]]; then
    printf '%s\n' "$2" >> "$FAKE_CURL_LOG"
    shift
  fi
  shift
done
exit "${FAKE_CURL_EXIT:-0}"
EOF
cat > "${fixture_dir}/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit "${FAKE_FLOCK_EXIT:-0}"
EOF
chmod +x "${fixture_dir}/bin/curl" "${fixture_dir}/bin/flock"
export PATH="${fixture_dir}/bin:${PATH}"
export FAKE_CURL_LOG="${fixture_dir}/requests.jsonl"
_sync_job_state_now() { echo 10000; }
sync_job_state_record_container_started

unset WEBHOOK_URL
sync_job_state_record_mailbox_run_finished failure
sync_job_notify
assert_calls 0

WEBHOOK_URL=https://webhook.example.test/fake-secret
WEBHOOK_FAILURE_THRESHOLD=3
sync_job_notify
assert_calls 0
sync_job_state_record_mailbox_run_finished failure
sync_job_notify
assert_calls 0
sync_job_state_record_mailbox_run_finished failure 23
sync_job_notify
assert_calls 1
assert_event alert failure
sync_job_notify
sync_job_state_record_mailbox_run_finished skipped
sync_job_notify
assert_calls 1

sync_job_state_record_mailbox_run_finished success
sync_job_notify
assert_calls 2
assert_event recovery failure
sync_job_notify
assert_calls 2

HEALTHCHECK_MAX_AGE_MINUTES=1
printf '%s\n' 9800 > "${SYNC_JOB_STATE_DIR}/last_success_at"
export FAKE_CURL_EXIT=22
output="$(sync_job_notify 2>&1)"
[[ "$output" != *fake-secret* ]] || fail "webhook URL leaked"
[[ "$output" == *retry* ]] || fail "delivery failure was not reported"
[[ ! -f "${SYNC_JOB_STATE_DIR}/notification_active" ]] || fail "failed delivery was marked sent"
assert_calls 3
assert_event alert stale
FAKE_CURL_EXIT=0
sync_job_notify
assert_calls 4
sync_job_notify
assert_calls 4
sync_job_state_record_mailbox_run_finished success
FAKE_CURL_EXIT=22
sync_job_notify 2>/dev/null
[[ -f "${SYNC_JOB_STATE_DIR}/notification_active" ]] || fail "failed recovery was not retained"
FAKE_CURL_EXIT=0
sync_job_notify
assert_calls 6
assert_event recovery stale

unset HEALTHCHECK_MAX_AGE_MINUTES
HEALTHCHECK_MAX_RUN_MINUTES=1
sync_job_state_record_mailbox_run_started
printf '%s\n' 9800 > "${SYNC_JOB_STATE_DIR}/last_attempt_at"
export FAKE_FLOCK_EXIT=1
sync_job_notify
assert_calls 6
FAKE_FLOCK_EXIT=0
sync_job_notify
assert_calls 7
assert_event alert run_timeout
sync_job_state_record_mailbox_run_finished success
sync_job_notify
assert_calls 8
assert_event recovery run_timeout

unset HEALTHCHECK_MAX_RUN_MINUTES
HEALTHCHECK_MAX_AGE_MINUTES=1
DRY_RUN=true
sync_job_state_record_mailbox_run_finished dry_run
printf '%s\n' 9800 > "${SYNC_JOB_STATE_DIR}/last_success_at"
sync_job_notify
assert_calls 8
printf '%s\n' 9800 > "${SYNC_JOB_STATE_DIR}/last_dry_run_at"
sync_job_notify
assert_calls 9
assert_event alert stale

rm "${SYNC_JOB_STATE_DIR}/notification_active" "${SYNC_JOB_STATE_DIR}/last_success_at" \
  "${SYNC_JOB_STATE_DIR}/last_dry_run_at" "${SYNC_JOB_STATE_DIR}/last_status"
DRY_RUN=false
sync_job_notify
assert_calls 9
printf '%s\n' 9800 > "${SYNC_JOB_STATE_DIR}/container_started_at"
sync_job_notify
assert_calls 10
assert_event alert stale

echo "ok - webhook notifications"
