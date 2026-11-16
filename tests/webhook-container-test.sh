#!/usr/bin/env bash
set -euo pipefail

image="${1:-mailbox-mirror:smoke-test}"
container_name="mailbox-mirror-webhook-${RANDOM}-$$"
if [[ -n "${MSYSTEM:-}" ]]; then export MSYS_NO_PATHCONV=1; fi

fail() { echo "not ok - $*" >&2; exit 1; }
cleanup() { docker rm -f "$container_name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

wait_for() {
  local condition="$1"
  for _ in {1..100}; do
    if docker exec "$container_name" bash -c "$condition" >/dev/null 2>&1; then return 0; fi
    sleep 0.1
  done
  docker logs "$container_name" >&2
  fail "container condition was not reached: $condition"
}

# Bootstrap the fakes before starting the installed entrypoint. No network or real credentials.
docker run --detach --name "$container_name" --network none \
  --env HOST1=imap.source.test --env USER1=source@example.test --env PASSWORD1=fake-source-secret \
  --env HOST2=imap.destination.test --env USER2=destination@example.test --env PASSWORD2=fake-target-secret \
  --env WEBHOOK_URL=https://webhook.example.test/fake-webhook-secret \
  --env WEBHOOK_FAILURE_THRESHOLD=2 --env RUN_ON_STARTUP=false --env CRON_SCHEDULE=@hourly \
  --entrypoint /bin/bash "$image" -c '
    while [[ ! -f /tmp/start-entrypoint ]]; do sleep 0.1; done
    export PATH="/tmp/test-bin:$PATH"
    exec /usr/local/bin/entrypoint.sh
  ' >/dev/null

docker exec -i "$container_name" bash <<'EOF'
set -euo pipefail
mkdir /tmp/test-bin
cat > /tmp/test-bin/curl <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
payload=""
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == --data-binary ]]; then payload="$2"; shift; fi
  shift
done
printf '%s\n' "$payload" >> /tmp/webhook-attempts
if [[ -f /tmp/curl-hang ]]; then
  touch /tmp/curl-hanging
  /bin/sleep 30
fi
if [[ -f /tmp/curl-fail ]]; then
  echo 'fake-webhook-secret must never reach container logs' >&2
  exit 22
fi
printf '%s\n' "$payload" >> /tmp/webhook-delivered
CURL
cat > /tmp/test-bin/sleep <<'SLEEP'
#!/usr/bin/env bash
# Accelerate only the monitor interval, keeping production code unchanged.
if [[ "$1" == 30 ]]; then exec /bin/sleep 0.1; fi
exec /bin/sleep "$@"
SLEEP
cat > /tmp/test-bin/imapsync <<'IMAPSYNC'
#!/usr/bin/env bash
echo 'Messages transferred : 2'
exit "$(cat /tmp/adapter-exit)"
IMAPSYNC
chmod +x /tmp/test-bin/*
echo 23 > /tmp/adapter-exit
touch /tmp/start-entrypoint
EOF

wait_for '/usr/local/bin/healthcheck.sh'
for _ in 1 2; do
  if docker exec --env PATH=/tmp/test-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$container_name" /usr/local/bin/run-imapsync.sh >/dev/null 2>&1; then
    fail "fake failed adapter unexpectedly succeeded"
  fi
done
wait_for '[[ -f /tmp/webhook-delivered && $(wc -l < /tmp/webhook-delivered) -eq 1 ]]'
sleep 0.4
docker exec "$container_name" bash -c '[[ $(wc -l < /tmp/webhook-delivered) -eq 1 ]]' \
  || fail "repeated checks delivered duplicate alerts"

docker exec "$container_name" bash -c 'touch /tmp/curl-fail; echo 0 > /tmp/adapter-exit'
docker exec --env PATH=/tmp/test-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  "$container_name" /usr/local/bin/run-imapsync.sh >/dev/null \
  || fail "notification failure affected a successful mailbox run"
wait_for '[[ $(wc -l < /tmp/webhook-attempts) -ge 2 ]]'
docker exec "$container_name" /usr/local/bin/healthcheck.sh \
  || fail "notification failure affected mailbox health"
docker exec "$container_name" bash -c '[[ -f /var/lib/imapsync/notification_active && $(wc -l < /tmp/webhook-delivered) -eq 1 ]]' \
  || fail "failed recovery was treated as delivered"
docker exec --env PATH=/tmp/test-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  "$container_name" bash -c '
    rm /tmp/curl-fail
    source /usr/local/lib/mailbox-mirror/sync-job-state.sh
    source /usr/local/lib/mailbox-mirror/notifications.sh
    for _ in {1..8}; do sync_job_notify & done
    wait
  '
wait_for '[[ $(wc -l < /tmp/webhook-delivered) -eq 2 ]]'
sleep 0.4
docker exec "$container_name" bash -c '[[ $(wc -l < /tmp/webhook-delivered) -eq 2 ]]' \
  || fail "repeated checks delivered duplicate recoveries"

docker exec "$container_name" perl -MJSON::PP -e '
  open my $file, "<", "/tmp/webhook-delivered" or die $!;
  my @events = map { decode_json($_) } <$file>;
  die "incorrect lifecycle events" unless @events == 2
    && $events[0]->{event} eq "alert" && $events[0]->{reason} eq "failure"
    && $events[1]->{event} eq "recovery" && $events[1]->{reason} eq "failure";
  for my $event (@events) {
    my $json = encode_json($event);
    die "secret data in payload" if $json =~ /secret|PASSWORD|WEBHOOK_URL|example[.]test/;
  }
' || fail "webhook payload contract failed"

# SIGTERM must stop the entire monitor group, including an in-flight HTTP client.
docker exec "$container_name" bash -c 'touch /tmp/curl-hang; echo 23 > /tmp/adapter-exit'
for _ in 1 2; do
  docker exec --env PATH=/tmp/test-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$container_name" /usr/local/bin/run-imapsync.sh >/dev/null 2>&1 || true
done
wait_for '[[ -f /tmp/curl-hanging ]]'
docker stop --time 5 "$container_name" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "$container_name")" == 0 ]] \
  || fail "container required forced shutdown with an active webhook request"
logs="$(docker logs "$container_name" 2>&1)"
[[ "$logs" != *fake-webhook-secret* && "$logs" != *fake-source-secret* && "$logs" != *fake-target-secret* ]] \
  || fail "secrets appeared in container logs"

echo "ok - webhook monitor lifecycle"
