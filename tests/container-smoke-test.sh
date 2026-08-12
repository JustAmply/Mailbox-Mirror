#!/usr/bin/env bash
set -euo pipefail

image="${1:-mailbox-mirror:smoke-test}"
container_name="mailbox-mirror-smoke-${RANDOM}-$$"

if [[ -n "${MSYSTEM:-}" ]]; then
  export MSYS_NO_PATHCONV=1
fi

fail() {
  echo "not ok - $*" >&2
  exit 1
}

cleanup() {
  docker rm -f "$container_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v docker >/dev/null 2>&1 \
  || fail "docker is required to run the container smoke test"
docker info >/dev/null 2>&1 \
  || fail "the Docker daemon must be running to run the container smoke test"
docker image inspect "$image" >/dev/null 2>&1 \
  || fail "image not found: ${image} (build it before running this test)"

docker run --detach \
  --name "$container_name" \
  --network none \
  --env HOST1=imap.source.test \
  --env USER1=source@example.test \
  --env PASSWORD1=source-password \
  --env HOST2=imap.destination.test \
  --env USER2=destination@example.test \
  --env PASSWORD2=destination-password \
  --env RUN_ON_STARTUP=false \
  --env CRON_SCHEDULE=@hourly \
  "$image" >/dev/null

health_output="healthcheck did not run"
healthy=false
for _ in {1..20}; do
  if health_output="$(docker exec "$container_name" /usr/local/bin/healthcheck.sh 2>&1)"; then
    healthy=true
    break
  fi

  if [[ "$(docker inspect --format '{{.State.Running}}' "$container_name")" != "true" ]]; then
    docker logs "$container_name" >&2
    fail "container exited before becoming healthy"
  fi

  sleep 0.25
done

if [[ "$healthy" != "true" ]]; then
  docker logs "$container_name" >&2
  fail "container did not become healthy: ${health_output}"
fi

docker exec "$container_name" \
  grep -Fq '@hourly root /usr/local/bin/cron-runner.sh' /etc/cron.d/imapsync \
  || fail "entrypoint did not install the configured cron schedule"

docker exec "$container_name" mkdir -p /tmp/fake-imapsync-bin
docker exec "$container_name" ln -s /bin/true /tmp/fake-imapsync-bin/imapsync
docker exec \
  --env PATH=/tmp/fake-imapsync-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  "$container_name" \
  /usr/local/bin/run-imapsync.sh >/dev/null \
  || fail "installed mailbox run failed with the fake imapsync adapter"
docker exec "$container_name" /usr/local/bin/healthcheck.sh \
  || fail "container became unhealthy after a successful mailbox run"

docker stop --time 5 "$container_name" >/dev/null \
  || fail "container did not stop within five seconds"

[[ "$(docker inspect --format '{{.State.Status}}' "$container_name")" == "exited" ]] \
  || fail "container is not in the exited state after docker stop"

container_logs="$(docker logs "$container_name" 2>&1)"
[[ "$container_logs" == *"Stopping container..."* ]] \
  || fail "entrypoint did not handle the stop signal"

echo "ok - container lifecycle"
