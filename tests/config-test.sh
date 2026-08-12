#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker/config.sh"

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

reset_env() {
  unset HOST1 USER1 PASSWORD1 HOST2 USER2 PASSWORD2
  unset PORT1 PORT2 SSL1 SSL2 MAXAGE_DAYS DRY_RUN
  unset CRON_SCHEDULE RUN_ON_STARTUP MAX_LOG_SIZE_MB HEALTHCHECK_MAX_AGE_MINUTES
}

set_required_env() {
  HOST1=imap.source.test
  USER1=source@example.test
  PASSWORD1=source-password
  HOST2=imap.destination.test
  USER2=destination@example.test
  PASSWORD2=destination-password
}

assert_invalid() {
  local expected="$1"
  local output

  if output="$(mailbox_mirror_config_load 2>&1)"; then
    fail "configuration should be invalid"
  fi
  assert_equal "$expected" "$output" "configuration error"
}

test_defaults() {
  reset_env
  set_required_env

  mailbox_mirror_config_load

  assert_equal "*/5 * * * *" "$CRON_SCHEDULE" "cron default"
  assert_equal "true" "$RUN_ON_STARTUP" "startup default"
  assert_equal "false" "$DRY_RUN" "dry-run default"
  assert_equal "true" "$SSL1" "source TLS default"
  assert_equal "true" "$SSL2" "destination TLS default"
  assert_equal "10" "$MAX_LOG_SIZE_MB" "log size default"
}

test_missing_required_value() {
  reset_env
  set_required_env
  unset PASSWORD2
  assert_invalid "Missing required env var: PASSWORD2"
}

test_invalid_boolean() {
  reset_env
  set_required_env
  DRY_RUN=yes
  assert_invalid "Invalid boolean value for DRY_RUN: yes (expected true or false)"
}

test_invalid_port() {
  reset_env
  set_required_env
  PORT1=65536
  assert_invalid "Invalid port value for PORT1: 65536 (expected 1 to 65535)"
}

test_invalid_maxage() {
  reset_env
  set_required_env
  MAXAGE_DAYS=0
  assert_invalid "Invalid integer value for MAXAGE_DAYS: 0 (expected a positive number)"
}

test_leading_zero_integer() {
  reset_env
  set_required_env
  MAX_LOG_SIZE_MB=08
  mailbox_mirror_config_load
  assert_equal "08" "$MAX_LOG_SIZE_MB" "leading-zero integer"
}

test_invalid_schedule() {
  reset_env
  set_required_env
  CRON_SCHEDULE="every minute"
  local output
  if output="$(mailbox_mirror_config_load 2>&1)"; then
    fail "invalid schedule should fail"
  fi
  assert_equal $'Invalid CRON_SCHEDULE: every minute\nExpected either a cron macro like @hourly or five cron fields.' "$output" "cron error"
}

test_defaults
test_missing_required_value
test_invalid_boolean
test_invalid_port
test_invalid_maxage
test_leading_zero_integer
test_invalid_schedule

echo "ok - runtime configuration contract"
