#!/usr/bin/env bash
set -euo pipefail

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

SYNC_JOB_STATE_DIR="${fixture_dir}/state"
SYNC_JOB_STATE_CRON_PID_FILE="${fixture_dir}/run/cron.pid"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker/sync-job-state.sh"

fail() {
  echo "not ok - $*" >&2
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$actual" != "$expected" ]]; then
    fail "${message}: expected '${expected}', got '${actual}'"
  fi
}

assert_file_matches() {
  local file="$1"
  local pattern="$2"

  [[ -f "$file" ]] || fail "missing state file: ${file}"
  [[ "$(<"$file")" =~ $pattern ]] || fail "invalid state file: ${file}"
}

assert_unhealthy() {
  local expected="$1"
  local output

  if output="$(sync_job_state_check_health 2>&1)"; then
    fail "state should be unhealthy"
  fi
  assert_equal "$expected" "$output" "health error"
}

sync_job_state_record_container_started
assert_file_matches "${SYNC_JOB_STATE_DIR}/container_started_at" '^[0-9]+$'

sync_job_state_record_cron_started "$$"
assert_equal "$$" "$(<"$SYNC_JOB_STATE_CRON_PID_FILE")" "cron pid"
sync_job_state_check_health

sync_job_state_record_mailbox_run_started
assert_file_matches "${SYNC_JOB_STATE_DIR}/last_attempt_at" '^[0-9]+$'
assert_equal "running" "$(<"${SYNC_JOB_STATE_DIR}/last_status")" "running status"

sync_job_state_record_mailbox_run_finished skipped
assert_equal "skipped" "$(<"${SYNC_JOB_STATE_DIR}/last_status")" "skipped status"

invalid_result_output=""
if invalid_result_output="$(sync_job_state_record_mailbox_run_finished invalid 2>&1)"; then
  fail "invalid mailbox run result should fail"
fi
assert_equal "Invalid mailbox run result: invalid" "$invalid_result_output" "invalid result"
assert_equal "skipped" "$(<"${SYNC_JOB_STATE_DIR}/last_status")" "status after invalid result"

sync_job_state_record_mailbox_run_finished failure
assert_unhealthy "Last mailbox run failed"

sync_job_state_record_mailbox_run_finished success
assert_equal "success" "$(<"${SYNC_JOB_STATE_DIR}/last_status")" "success status"
assert_file_matches "${SYNC_JOB_STATE_DIR}/last_success_at" '^[0-9]+$'

HEALTHCHECK_MAX_AGE_MINUTES=1
sync_job_state_check_health
printf '%s\n' "$(( $(date +%s) - 120 ))" > "${SYNC_JOB_STATE_DIR}/last_success_at"
assert_unhealthy "Last successful mailbox run is older than 1 minute(s)"

printf '%s\n' "invalid" > "${SYNC_JOB_STATE_DIR}/last_success_at"
assert_unhealthy "Invalid mailbox run timestamp: invalid"

printf '%s\n' "invalid" > "${SYNC_JOB_STATE_DIR}/last_status"
assert_unhealthy "Invalid mailbox run status: invalid"

printf '%s\n' "invalid" > "$SYNC_JOB_STATE_CRON_PID_FILE"
assert_unhealthy "Invalid cron pid: invalid"

echo "ok - sync job state contract"
