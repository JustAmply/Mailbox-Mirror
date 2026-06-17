#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker/mailbox-run.sh"

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
  unset PORT1 PORT2 SSL1 SSL2 AUTHMECH1 AUTHMECH2 FOLDER_FILTER MAXAGE_DAYS
  unset DRY_RUN IMAPSYNC_EXTRA_ARGS
}

set_required_env() {
  HOST1=imap.source.tld
  USER1=source@example.com
  PASSWORD1=source-password
  HOST2=imap.destination.tld
  USER2=destination@example.com
  PASSWORD2=destination-password
}

command_as_lines() {
  local item
  for item in "$@"; do
    printf '%s\n' "$item"
  done
}

test_minimal_command_uses_default_ssl() {
  reset_env
  set_required_env

  mailbox_run_validate_env
  local cmd
  mailbox_run_build_command cmd

  local expected actual
  expected=$'imapsync\n--host1\nimap.source.tld\n--user1\nsource@example.com\n--password1\nsource-password\n--host2\nimap.destination.tld\n--user2\ndestination@example.com\n--password2\ndestination-password\n--automap\n--syncinternaldates\n--useuid\n--nofoldersizes\n--ssl1\n--ssl2'
  actual="$(command_as_lines "${cmd[@]}")"

  assert_equal "$expected" "$actual" "minimal command"
}

test_optional_args_append_in_order() {
  reset_env
  set_required_env
  PORT1=1143
  PORT2=2993
  SSL1=false
  SSL2=true
  AUTHMECH1=LOGIN
  AUTHMECH2=XOAUTH2
  FOLDER_FILTER=INBOX
  MAXAGE_DAYS=30
  DRY_RUN=true
  IMAPSYNC_EXTRA_ARGS="--delete2 --expunge2"

  mailbox_run_validate_env
  local cmd
  mailbox_run_build_command cmd

  local expected actual
  expected=$'imapsync\n--host1\nimap.source.tld\n--user1\nsource@example.com\n--password1\nsource-password\n--host2\nimap.destination.tld\n--user2\ndestination@example.com\n--password2\ndestination-password\n--automap\n--syncinternaldates\n--useuid\n--nofoldersizes\n--port1\n1143\n--port2\n2993\n--ssl2\n--authmech1\nLOGIN\n--authmech2\nXOAUTH2\n--folder\nINBOX\n--maxage\n30\n--dry\n--delete2\n--expunge2'
  actual="$(command_as_lines "${cmd[@]}")"

  assert_equal "$expected" "$actual" "optional command"
}

test_missing_required_env_fails() {
  reset_env
  set_required_env
  unset PASSWORD2

  local output
  if output="$(mailbox_run_validate_env 2>&1)"; then
    fail "missing required env should fail"
  fi

  assert_equal "Missing required env var: PASSWORD2" "$output" "missing env message"
}

test_invalid_bool_fails() {
  reset_env
  set_required_env
  DRY_RUN=yes

  local output
  if output="$(mailbox_run_validate_env 2>&1)"; then
    fail "invalid bool should fail"
  fi

  assert_equal "Invalid boolean value for DRY_RUN: yes (expected true or false)" "$output" "invalid bool message"
}

test_minimal_command_uses_default_ssl
test_optional_args_append_in_order
test_missing_required_env_fails
test_invalid_bool_fails

echo "ok - mailbox-run contract"
