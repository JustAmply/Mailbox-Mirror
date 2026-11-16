#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "not ok - $*" >&2
  exit 1
}

prepare_adapter() {
  mkdir -p /testbin /tmp/mailbox-runtime-test
  cat > /testbin/imapsync <<'ADAPTER'
#!/usr/bin/env bash
set -euo pipefail
fixture=/tmp/mailbox-runtime-test
child_pid=""
stop() {
  trap '' TERM INT
  touch "$fixture/terminated"
  if [[ -n "$child_pid" ]]; then
    kill "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi
  exit 143
}
trap stop TERM INT
echo "$$" > "$fixture/adapter_pid"
touch "$fixture/started"
case "$(<"$fixture/mode")" in
  hold)
    sleep 120 &
    child_pid=$!
    echo "$child_pid" > "$fixture/child_pid"
    wait "$child_pid"
    ;;
  gate)
    while [[ ! -f "$fixture/release" ]]; do sleep 0.05; done
    ;;
  success) ;;
  *) exit 2 ;;
esac
echo 'Messages transferred : 7'
ADAPTER
  chmod +x /testbin/imapsync
  export PATH="/testbin:$PATH"
}

wait_for_file() {
  local file="$1"
  for _ in {1..100}; do
    [[ ! -f "$file" ]] || return 0
    sleep 0.05
  done
  fail "timed out waiting for ${file}"
}

prepare_delayed_session() {
  # Hold the child before setsid creates its process group, without creating
  # descendants that could hide whether the direct-PID fallback worked.
  cat > /testbin/setsid <<'DELAYED_SESSION'
#!/usr/bin/env bash
set -euo pipefail
echo "$$" > /tmp/mailbox-runtime-test/session_pid
touch /tmp/mailbox-runtime-test/session_waiting
exec sleep 120
DELAYED_SESSION
  chmod +x /testbin/setsid
}

if [[ "${1:-}" == --startup || "${1:-}" == --startup-early || "${1:-}" == --startup-before-session ]]; then
  prepare_adapter
  echo hold > /tmp/mailbox-runtime-test/mode
  if [[ "$1" == --startup-early ]]; then
    mv /usr/local/bin/run-imapsync.sh /usr/local/bin/run-imapsync-real.sh
    cat > /usr/local/bin/run-imapsync.sh <<'DELAYED_RUN'
#!/usr/bin/env bash
set -euo pipefail
touch /tmp/mailbox-runtime-test/wrapper_waiting
sleep 120
exec /usr/local/bin/run-imapsync-real.sh
DELAYED_RUN
    chmod +x /usr/local/bin/run-imapsync.sh
  fi
  if [[ "$1" == --startup-before-session ]]; then
    prepare_delayed_session
  fi
  exec /usr/local/bin/entrypoint.sh
fi

if [[ "${1:-}" == --inside ]]; then
  prepare_adapter
  fixture=/tmp/mailbox-runtime-test
  export SYNC_JOB_STATE_DIR="$fixture/state" LOCK_FILE="$fixture/shared.lock"
  export SHUTDOWN_GRACE_SECONDS=1

  assert_state() {
    [[ "$(<"$SYNC_JOB_STATE_DIR/$1")" == "$2" ]] || fail "${1} must be ${2}"
  }
  reset_case() {
    rm -rf "$SYNC_JOB_STATE_DIR"
    rm -f "$fixture/started" "$fixture/terminated" "$fixture/release" "$fixture/held" "$fixture/unlock"
    unset RUN_TIMEOUT_SECONDS LOCK_WAIT_SECONDS
    echo "$1" > "$fixture/mode"
  }
  assert_not_running() {
    local pid="$1" state
    if [[ -f "/proc/$pid/stat" ]]; then
      state="$(awk '{print $3}' "/proc/$pid/stat")"
      [[ "$state" == Z ]] || fail "adapter descendant ${pid} is still running"
    fi
  }
  hold_shared_lock() {
    flock "$LOCK_FILE" bash -c 'touch "$1/held"; while [[ ! -f "$1/unlock" ]]; do sleep 0.05; done' bash "$fixture" &
    holder_pid=$!
    wait_for_file "$fixture/held"
  }

  reset_case hold
  export RUN_TIMEOUT_SECONDS=1
  exit_code=0
  /usr/local/bin/run-imapsync.sh > "$fixture/run.log" 2>&1 || exit_code=$?
  [[ "$exit_code" == 124 ]] || fail "timeout must return 124, got ${exit_code}"
  assert_state last_status failure
  assert_state last_exit_code 124
  [[ -f "$fixture/terminated" ]] || fail "timeout did not signal the adapter"
  assert_not_running "$(<"$fixture/child_pid")"
  echo 'ok - timeout records failure and terminates adapter descendants'

  reset_case gate
  /usr/local/bin/run-imapsync.sh > "$fixture/run.log" 2>&1 &
  run_pid=$!
  wait_for_file "$fixture/started"
  active_pid="$(<"$SYNC_JOB_STATE_DIR/active_pid")"
  attempted_at="$(<"$SYNC_JOB_STATE_DIR/last_attempt_at")"
  /usr/local/bin/run-imapsync.sh > "$fixture/overlap.log" 2>&1
  assert_state last_status running
  assert_state active_pid "$active_pid"
  assert_state last_attempt_at "$attempted_at"
  [[ ! -f "$SYNC_JOB_STATE_DIR/last_finished_at" ]] || fail 'overlap overwrote the active result'
  touch "$fixture/release"
  wait "$run_pid"
  assert_state last_status success
  assert_state last_messages_transferred 7
  echo 'ok - local overlap preserves the active run and its state'

  reset_case success
  hold_shared_lock
  export LOCK_WAIT_SECONDS=5
  /usr/local/bin/run-imapsync.sh > "$fixture/run.log" 2>&1 &
  run_pid=$!
  wait_for_file "$SYNC_JOB_STATE_DIR/active_pid"
  [[ ! -f "$fixture/started" ]] || fail 'adapter ran before acquiring the shared lock'
  touch "$fixture/unlock"
  wait "$holder_pid"
  wait "$run_pid"
  assert_state last_status success
  [[ -f "$fixture/started" ]] || fail 'waiting run did not resume after lock release'
  echo 'ok - shared lock waiter resumes when the previous mailbox finishes'

  reset_case success
  hold_shared_lock
  export LOCK_WAIT_SECONDS=1
  /usr/local/bin/run-imapsync.sh > "$fixture/run.log" 2>&1
  assert_state last_status skipped
  assert_state consecutive_skips 1
  /usr/local/bin/run-imapsync.sh >> "$fixture/run.log" 2>&1
  assert_state consecutive_skips 2
  [[ ! -f "$fixture/started" ]] || fail 'adapter ran while the shared lock was held'
  touch "$fixture/unlock"
  wait "$holder_pid"
  /usr/local/bin/run-imapsync.sh >> "$fixture/run.log" 2>&1
  assert_state last_status success
  assert_state consecutive_skips 0
  echo 'ok - expired shared lock waits record skips and recovery clears them'

  reset_case success
  hold_shared_lock
  export LOCK_WAIT_SECONDS=120
  /usr/local/bin/run-imapsync.sh > "$fixture/run.log" 2>&1 &
  run_pid=$!
  wait_for_file "$SYNC_JOB_STATE_DIR/active_pid"
  # Let the run enter flock rather than only testing the pre-lock signal handler.
  sleep 0.2
  kill -TERM "$(<"$SYNC_JOB_STATE_DIR/active_pid")"
  exit_code=0
  wait "$run_pid" || exit_code=$?
  [[ "$exit_code" == 143 ]] || fail "interrupted lock wait must return 143, got ${exit_code}"
  assert_state last_status failure
  assert_state last_exit_code 143
  [[ ! -f "$fixture/started" ]] || fail 'interrupted lock waiter started the adapter'
  touch "$fixture/unlock"
  wait "$holder_pid"
  echo 'ok - SIGTERM interrupts a pending shared lock wait'

  reset_case success
  prepare_delayed_session
  /usr/local/bin/run-imapsync.sh > "$fixture/run.log" 2>&1 &
  run_pid=$!
  wait_for_file "$fixture/session_waiting"
  session_pid="$(<"$fixture/session_pid")"
  if kill -0 -- "-$session_pid" 2>/dev/null; then
    fail 'delayed adapter session already has a process group'
  fi
  kill -TERM "$(<"$SYNC_JOB_STATE_DIR/active_pid")"
  wait_for_file "$SYNC_JOB_STATE_DIR/last_finished_at"
  exit_code=0
  wait "$run_pid" || exit_code=$?
  [[ "$exit_code" == 143 ]] || fail "pre-session interruption must return 143, got ${exit_code}"
  assert_state last_status failure
  assert_state last_exit_code 143
  assert_not_running "$session_pid"
  [[ ! -f "$fixture/started" ]] || fail 'adapter started after pre-session interruption'
  echo 'ok - SIGTERM before adapter session creation stops the direct child'
  exit 0
fi

image="${1:-mailbox-mirror:smoke-test}"
prefix="mailbox-mirror-runtime-${RANDOM}-$$"
fixture_dir="$(mktemp -d)"
if [[ -n "${MSYSTEM:-}" ]]; then
  export MSYS_NO_PATHCONV=1
  script_path="$(cygpath -w "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")")"
  copy_path="$(cygpath -w "$fixture_dir")"
else
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  copy_path="$fixture_dir"
fi

cleanup() {
  local result=$?
  if (( result != 0 )); then
    docker logs "${prefix}-checks" >&2 2>/dev/null || true
    docker logs "${prefix}-startup" >&2 2>/dev/null || true
    docker logs "${prefix}-early" >&2 2>/dev/null || true
    docker logs "${prefix}-before-session" >&2 2>/dev/null || true
  fi
  docker rm -f "${prefix}-checks" "${prefix}-startup" "${prefix}-early" "${prefix}-before-session" >/dev/null 2>&1 || true
  rm -rf "$fixture_dir"
}
trap cleanup EXIT

create_test_container() {
  local name="$1" mode="$2"
  docker create --name "$name" --network none \
    --env HOST1=imap.source.test --env USER1=source@example.test --env PASSWORD1=FAKE-source-password \
    --env HOST2=imap.destination.test --env USER2=destination@example.test --env PASSWORD2=FAKE-destination-password \
    --env CRON_SCHEDULE=@yearly --env SHUTDOWN_GRACE_SECONDS=08 \
    --entrypoint bash "$image" /tmp/runtime-container-test.sh "$mode" >/dev/null
  docker cp "$script_path" "$name:/tmp/runtime-container-test.sh"
}

create_test_container "${prefix}-checks" --inside
docker start "${prefix}-checks" >/dev/null
result="$(timeout 45 docker wait "${prefix}-checks")"
docker logs "${prefix}-checks"
[[ "$result" == 0 ]] || fail "runtime checks exited ${result}"

create_test_container "${prefix}-startup" --startup
docker start "${prefix}-startup" >/dev/null
started=false
for _ in {1..40}; do
  if docker exec "${prefix}-startup" test -f /tmp/mailbox-runtime-test/child_pid; then
    started=true
    break
  fi
  sleep 0.1
done
[[ "$started" == true ]] || fail 'initial adapter did not start'
docker stop --time 15 "${prefix}-startup" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "${prefix}-startup")" == 0 ]] \
  || fail 'container did not finish its graceful shutdown'
docker cp "${prefix}-startup:/var/lib/imapsync" "$copy_path/state"
docker cp "${prefix}-startup:/tmp/mailbox-runtime-test/terminated" "$copy_path/terminated"
[[ "$(<"$fixture_dir/state/last_status")" == failure ]] || fail 'initial run shutdown did not record failure'
[[ "$(<"$fixture_dir/state/last_exit_code")" == 143 ]] || fail 'initial run shutdown did not record SIGTERM'
[[ ! -f "$fixture_dir/state/active_pid" ]] || fail 'initial run retained a stale active PID'
[[ -f "$fixture_dir/terminated" ]] || fail 'initial adapter did not receive SIGTERM'
echo 'ok - SIGTERM during initial sync stops the adapter and records failure before exit'

create_test_container "${prefix}-early" --startup-early
docker start "${prefix}-early" >/dev/null
started=false
for _ in {1..40}; do
  if docker exec "${prefix}-early" test -f /tmp/mailbox-runtime-test/wrapper_waiting; then
    started=true
    break
  fi
  sleep 0.1
done
[[ "$started" == true ]] || fail 'delayed initial run wrapper did not start'
docker exec "${prefix}-early" test ! -e /var/lib/imapsync/active_pid \
  || fail 'early shutdown fixture already registered an active run'
docker stop --time 15 "${prefix}-early" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "${prefix}-early")" == 0 ]] \
  || fail 'shutdown before active run registration did not finish gracefully'
docker cp "${prefix}-early:/tmp/mailbox-runtime-test" "$copy_path/early"
[[ ! -f "$fixture_dir/early/started" ]] || fail 'adapter started after early shutdown'
echo 'ok - SIGTERM before initial run registration exits cleanly without starting the adapter'

create_test_container "${prefix}-before-session" --startup-before-session
docker start "${prefix}-before-session" >/dev/null
started=false
for _ in {1..40}; do
  if docker exec "${prefix}-before-session" test -f /tmp/mailbox-runtime-test/session_waiting; then
    started=true
    break
  fi
  sleep 0.1
done
[[ "$started" == true ]] || fail 'delayed session fixture did not start'
docker exec "${prefix}-before-session" test ! -e /var/lib/imapsync/active_pid \
  || fail 'pre-session shutdown fixture already registered an active run'
docker stop --time 15 "${prefix}-before-session" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "${prefix}-before-session")" == 0 ]] \
  || fail 'shutdown before session creation did not finish gracefully'
docker cp "${prefix}-before-session:/tmp/mailbox-runtime-test" "$copy_path/before-session"
[[ ! -f "$fixture_dir/before-session/started" ]] || fail 'adapter started after pre-session shutdown'
echo 'ok - SIGTERM before initial session creation exits cleanly without starting the adapter'
