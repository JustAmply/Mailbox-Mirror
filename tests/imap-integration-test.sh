#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${1:-mailbox-mirror:smoke-test}"
fixture_image="mailbox-mirror:imap-fixture"
prefix="mailbox-mirror-imap-${RANDOM}-$$"
source_container="${prefix}-source"
destination_container="${prefix}-destination"
run_container="${prefix}-run"
run_options=()

if [[ -n "${MSYSTEM:-}" ]]; then
  export MSYS_NO_PATHCONV=1
fi

cleanup() {
  local result=$?
  if (( result != 0 )); then
    for container in "$run_container" "$source_container" "$destination_container"; do
      docker logs --tail 80 "$container" >&2 2>/dev/null || true
    done
  fi
  docker rm -f "$run_container" "$source_container" "$destination_container" >/dev/null 2>&1 || true
  docker network rm "$prefix" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker info >/dev/null
docker image inspect "$image" >/dev/null
(cd "$repo_root" && docker build --tag "$fixture_image" tests/imap-fixtures)

# No exposed ports and no outbound network access during the test.
docker network create --internal "$prefix" >/dev/null
docker run --detach --name "$source_container" --network "$prefix" --network-alias source "$fixture_image" >/dev/null
docker run --detach --name "$destination_container" --network "$prefix" --network-alias destination "$fixture_image" >/dev/null
docker exec "$source_container" python3 /test/mailbox.py ready
docker exec "$destination_container" python3 /test/mailbox.py ready
docker exec "$source_container" python3 /test/mailbox.py seed

start_run() {
  docker run --detach --name "$run_container" --network "$prefix" \
    --env HOST1=source --env PORT1=143 --env USER1=fixture \
    --env PASSWORD1=FAKE-integration-password --env SSL1=false \
    --env HOST2=destination --env PORT2=143 --env USER2=fixture \
    --env PASSWORD2=FAKE-integration-password --env SSL2=false \
    --env "IMAPSYNC_EXTRA_ARGS=--nossl1 --nossl2 --notls1 --notls2 --nolog ${1:-}" \
    "${run_options[@]}" --entrypoint /usr/local/bin/run-imapsync.sh "$image" >/dev/null
}

finish_run() {
  local exit_code
  exit_code="$(timeout 120 docker wait "$run_container")"
  if [[ "$exit_code" != "0" ]]; then
    echo "not ok - real IMAP mailbox run exited with ${exit_code}" >&2
    return 1
  fi
  docker rm "$run_container" >/dev/null
}

verify_mailboxes() {
  docker exec "$source_container" python3 /test/mailbox.py verify
}

# Emulate an installation's previous forced UID mode, then upgrade to the default.
start_run "--useuid"
finish_run
verify_mailboxes
start_run
finish_run
verify_mailboxes

docker exec "$source_container" python3 /test/mailbox.py change-flags
start_run
finish_run
verify_mailboxes

# Interrupt after at least one message arrived, while more are still pending.
# Abrupt process loss models a crash; lifecycle signal handling has separate tests.
docker exec "$source_container" python3 /test/mailbox.py seed-recovery
start_run "--maxbytespersecond 32768 --maxbytesafter 0"
docker exec "$destination_container" python3 /test/mailbox.py wait-partial
docker kill "$run_container" >/dev/null
[[ "$(docker wait "$run_container")" != "0" ]]
docker rm "$run_container" >/dev/null
start_run
finish_run
verify_mailboxes
echo "ok - real IMAP recovery after an interrupted transfer"

docker exec "$destination_container" python3 /test/mailbox.py seed-destination-only
start_run
finish_run
docker exec "$source_container" python3 /test/mailbox.py verify-additive
run_options=(--env SYNC_MODE=mirror --env ALLOW_DELETIONS=true)
start_run
finish_run
verify_mailboxes
echo "ok - additive preserves and explicit mirror removes destination-only mail"

run_options=(
  --env USER2=routed
  --env $'FOLDER_INCLUDE=INBOX\nProjects\nProjects/Archive'
  --env 'FOLDER_EXCLUDE=Archive$'
  --env 'FOLDER_MAP=Projects=Mapped Projects'
  --env DESTINATION_PREFIX=Source/
)
start_run
finish_run
docker exec "$source_container" python3 /test/mailbox.py verify-routing
