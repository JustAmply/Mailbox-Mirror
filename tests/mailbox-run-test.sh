#!/usr/bin/env bash
set -euo pipefail

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

SYNC_JOB_STATE_DIR="${fixture_dir}/state"
SYNC_JOB_STATE_CRON_PID_FILE="${fixture_dir}/run/cron.pid"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/docker/mailbox-run.sh"

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

reset_run() {
  rm -rf "$SYNC_JOB_STATE_DIR"
  rm -f "${fixture_dir}/imapsync.args" "${fixture_dir}/run.log"
  unset HOST1 USER1 PASSWORD1 HOST2 USER2 PASSWORD2
  unset PORT1 PORT2 SSL1 SSL2 AUTHMECH1 AUTHMECH2 FOLDER_FILTER MAXAGE_DAYS
  unset DRY_RUN IMAPSYNC_EXTRA_ARGS CRON_SCHEDULE RUN_ON_STARTUP MAX_LOG_SIZE_MB
  unset HEALTHCHECK_MAX_AGE_MINUTES
  HOST1=imap.source.test
  USER1=source@example.test
  PASSWORD1=source-password
  HOST2=imap.destination.test
  USER2=destination@example.test
  PASSWORD2=destination-password
  LOCK_FILE="${fixture_dir}/locks/mailbox-run.lock"
  FAKE_FLOCK_EXIT=0
  FAKE_IMAPSYNC_EXIT=0
  export HOST1 USER1 PASSWORD1 HOST2 USER2 PASSWORD2 LOCK_FILE
  export FAKE_FLOCK_EXIT FAKE_IMAPSYNC_EXIT
}

mkdir -p "${fixture_dir}/bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$@" > "$FAKE_IMAPSYNC_ARGS"' \
  'exit "${FAKE_IMAPSYNC_EXIT:-0}"' \
  > "${fixture_dir}/bin/imapsync"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'exit "${FAKE_FLOCK_EXIT:-0}"' \
  > "${fixture_dir}/bin/flock"
chmod +x "${fixture_dir}/bin/imapsync" "${fixture_dir}/bin/flock"
export PATH="${fixture_dir}/bin:${PATH}"
export FAKE_IMAPSYNC_ARGS="${fixture_dir}/imapsync.args"

test_successful_mailbox_run() {
  reset_run

  mailbox_run_execute > "${fixture_dir}/run.log"

  assert_equal "success" "$(<"${SYNC_JOB_STATE_DIR}/last_status")" "successful status"
  [[ "$(<"${SYNC_JOB_STATE_DIR}/last_success_at")" =~ ^[0-9]+$ ]] \
    || fail "successful run should record its completion time"
  local expected_args
  expected_args=$'--host1\nimap.source.test\n--user1\nsource@example.test\n--password1\nsource-password\n--host2\nimap.destination.test\n--user2\ndestination@example.test\n--password2\ndestination-password\n--automap\n--syncinternaldates\n--useuid\n--nofoldersizes\n--ssl1\n--ssl2'
  assert_equal "$expected_args" "$(<"$FAKE_IMAPSYNC_ARGS")" "minimal adapter arguments"
  grep -Fq "imapsync finished successfully." "${fixture_dir}/run.log" \
    || fail "successful run should be logged"
}

test_optional_configuration_reaches_adapter() {
  reset_run
  PORT1=1143
  PORT2=2993
  SSL1=false
  AUTHMECH1=LOGIN
  AUTHMECH2=XOAUTH2
  FOLDER_FILTER=INBOX
  MAXAGE_DAYS=30
  DRY_RUN=true
  IMAPSYNC_EXTRA_ARGS="--delete2 --expunge2"
  export PORT1 PORT2 SSL1 AUTHMECH1 AUTHMECH2 FOLDER_FILTER MAXAGE_DAYS DRY_RUN IMAPSYNC_EXTRA_ARGS

  mailbox_run_execute > "${fixture_dir}/run.log"

  local expected_args
  expected_args=$'--host1\nimap.source.test\n--user1\nsource@example.test\n--password1\nsource-password\n--host2\nimap.destination.test\n--user2\ndestination@example.test\n--password2\ndestination-password\n--automap\n--syncinternaldates\n--useuid\n--nofoldersizes\n--port1\n1143\n--port2\n2993\n--ssl2\n--authmech1\nLOGIN\n--authmech2\nXOAUTH2\n--folder\nINBOX\n--maxage\n30\n--dry\n--delete2\n--expunge2'
  assert_equal "$expected_args" "$(<"$FAKE_IMAPSYNC_ARGS")" "optional adapter arguments"
  grep -Fq "Starting imapsync in dry-run mode..." "${fixture_dir}/run.log" \
    || fail "dry run should be logged"
}

test_invalid_configuration_fails_run() {
  reset_run
  unset PASSWORD2

  local output
  if output="$(mailbox_run_execute 2>&1)"; then
    fail "invalid configuration should fail the mailbox run"
  fi

  assert_equal "Missing required env var: PASSWORD2" "$output" "configuration error"
  assert_equal "failure" "$(<"${SYNC_JOB_STATE_DIR}/last_status")" "invalid configuration status"
  [[ ! -e "$FAKE_IMAPSYNC_ARGS" ]] || fail "adapter should not run with invalid configuration"
}

test_active_lock_skips_adapter() {
  reset_run
  FAKE_FLOCK_EXIT=1
  export FAKE_FLOCK_EXIT

  mailbox_run_execute > "${fixture_dir}/run.log"

  assert_equal "skipped" "$(<"${SYNC_JOB_STATE_DIR}/last_status")" "locked status"
  [[ ! -e "$FAKE_IMAPSYNC_ARGS" ]] || fail "adapter should not run while lock is active"
  grep -Fq "Previous mailbox run still active" "${fixture_dir}/run.log" \
    || fail "skipped run should be logged"
}

test_adapter_failure_fails_run() {
  reset_run
  FAKE_IMAPSYNC_EXIT=23
  export FAKE_IMAPSYNC_EXIT

  local adapter_exit
  if mailbox_run_execute > "${fixture_dir}/run.log"; then
    fail "adapter failure should fail the mailbox run"
  else
    adapter_exit=$?
  fi

  assert_equal "23" "$adapter_exit" "adapter exit code"
  assert_equal "failure" "$(<"${SYNC_JOB_STATE_DIR}/last_status")" "adapter failure status"
}

test_successful_mailbox_run
test_optional_configuration_reaches_adapter
test_invalid_configuration_fails_run
test_active_lock_skips_adapter
test_adapter_failure_fails_run

echo "ok - mailbox run contract"
