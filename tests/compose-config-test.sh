#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

fail() {
  echo "not ok - $*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 \
  || fail "docker is required to validate the Compose configuration"
docker compose version >/dev/null 2>&1 \
  || fail "the Docker Compose plugin is required to validate the Compose configuration"

cp "${repo_root}/docker-compose.yml" "${fixture_dir}/docker-compose.yml"
cp "${repo_root}/docker-compose.multi-mailbox.yml" "${fixture_dir}/docker-compose.multi-mailbox.yml"
cat > "${fixture_dir}/.env" <<'EOF'
HOST1=imap.source.test
USER1=source@example.test
PASSWORD1=source-password
HOST2=imap.destination.test
USER2=destination@example.test
PASSWORD2=destination-password
RUN_ON_STARTUP=false
CRON_SCHEDULE=17 3 * * *
PASSWORD1_FILE=/run/secrets/source_fake
MAILBOX_A_PASSWORD1_FILE=/run/secrets/mailbox_a_fake
RUN_TIMEOUT_SECONDS=901
LOCK_WAIT_SECONDS=41
HEALTHCHECK_MAX_RUN_MINUTES=81
MAILBOX_A_RUN_TIMEOUT_SECONDS=902
MAILBOX_A_LOCK_WAIT_SECONDS=42
MAILBOX_A_HEALTHCHECK_MAX_AGE_MINUTES=31
MAILBOX_A_HEALTHCHECK_MAX_RUN_MINUTES=82
MAILBOX_A_SHUTDOWN_GRACE_SECONDS=11
FOLDER_INCLUDE=Sent Items
DESTINATION_PREFIX=Single/
SYNC_MODE=mirror
ALLOW_DELETIONS=true
MAILBOX_A_FOLDER_INCLUDE=Sent Items
MAILBOX_A_FOLDER_EXCLUDE=^Spam$
MAILBOX_A_FOLDER_MAP=Sent Items=Archive/Sent
MAILBOX_A_DESTINATION_PREFIX=Source/
MAILBOX_A_SYNC_MODE=mirror
MAILBOX_A_ALLOW_DELETIONS=true
MAILBOX_A_FOLDER_FILTER=
WEBHOOK_URL=https://monitor.example.test/single
WEBHOOK_FAILURE_THRESHOLD=4
MAILBOX_A_WEBHOOK_URL=https://monitor.example.test/a
MAILBOX_A_WEBHOOK_FAILURE_THRESHOLD=5
MAILBOX_A_AUTHMECH1=LOGIN
MAILBOX_A_AUTHMECH2=PLAIN
EOF

compose_config="$(docker compose --project-directory "$fixture_dir" config --format json)"

[[ "$compose_config" == *'"RUN_ON_STARTUP": "false"'* ]] \
  || fail "docker-compose.yml must preserve RUN_ON_STARTUP from .env"
[[ "$compose_config" == *'"CRON_SCHEDULE": "17 3 * * *"'* ]] \
  || fail "docker-compose.yml must preserve CRON_SCHEDULE from .env"

multi_compose_config="$(docker compose \
  --project-directory "$fixture_dir" \
  --file "${fixture_dir}/docker-compose.multi-mailbox.yml" \
  config --format json)"

[[ "$multi_compose_config" == *'"AUTHMECH1": "LOGIN"'* ]] \
  || fail "docker-compose.multi-mailbox.yml must map MAILBOX_A_AUTHMECH1"
[[ "$multi_compose_config" == *'"AUTHMECH2": "PLAIN"'* ]] \
  || fail "docker-compose.multi-mailbox.yml must map MAILBOX_A_AUTHMECH2"

[[ "$compose_config" == *'"PASSWORD1_FILE": "/run/secrets/source_fake"'* ]] || fail "single mailbox secret override lost"
[[ "$multi_compose_config" == *'"PASSWORD1_FILE": "/run/secrets/mailbox_a_fake"'* ]] || fail "multi mailbox secret mapping lost"
for entry in '"RUN_TIMEOUT_SECONDS": "901"' '"LOCK_WAIT_SECONDS": "41"' '"HEALTHCHECK_MAX_RUN_MINUTES": "81"'; do
  [[ "$compose_config" == *"$entry"* ]] || fail "single mailbox override lost: $entry"
done
for entry in '"RUN_TIMEOUT_SECONDS": "902"' '"LOCK_WAIT_SECONDS": "42"' '"HEALTHCHECK_MAX_AGE_MINUTES": "31"' '"HEALTHCHECK_MAX_RUN_MINUTES": "82"' '"SHUTDOWN_GRACE_SECONDS": "11"'; do
  [[ "$multi_compose_config" == *"$entry"* ]] || fail "multi mailbox override lost: $entry"
done
for entry in '"FOLDER_INCLUDE": "Sent Items"' '"DESTINATION_PREFIX": "Single/"' '"SYNC_MODE": "mirror"' '"ALLOW_DELETIONS": "true"'; do
  [[ "$compose_config" == *"$entry"* ]] || fail "folder override lost: $entry"
done
for entry in '"FOLDER_INCLUDE": "Sent Items"' '"FOLDER_EXCLUDE": "^Spam$$"' '"FOLDER_MAP": "Sent Items=Archive/Sent"' '"DESTINATION_PREFIX": "Source/"' '"SYNC_MODE": "mirror"' '"ALLOW_DELETIONS": "true"' '"FOLDER_FILTER": ""' '"FOLDER_FILTER": "INBOX"'; do
  [[ "$multi_compose_config" == *"$entry"* ]] || fail "multi folder override/default lost: $entry"
done
[[ "$compose_config" == *'"WEBHOOK_URL": "https://monitor.example.test/single"'* && "$compose_config" == *'"WEBHOOK_FAILURE_THRESHOLD": "4"'* ]] || fail "single webhook overrides lost"
[[ "$multi_compose_config" == *'"WEBHOOK_URL": "https://monitor.example.test/a"'* && "$multi_compose_config" == *'"WEBHOOK_FAILURE_THRESHOLD": "5"'* ]] || fail "multi webhook overrides lost"
[[ "$compose_config" == *'"stop_grace_period": "30s"'* && "$multi_compose_config" == *'"stop_grace_period": "30s"'* ]] || fail "shutdown grace period lost"
# Exercise the actual onboarding templates, including Compose's file selection.
example_dir="${fixture_dir}/examples"
mkdir -p "$example_dir"
cp "${repo_root}/docker-compose.yml" "${repo_root}/docker-compose.multi-mailbox.yml" "$example_dir/"
cp "${repo_root}/.env.example" "${example_dir}/.env"
cat >> "${example_dir}/.env" <<'EOF'
PASSWORD1='fake $literal #password'
EOF
example_config="$(docker compose --project-directory "$example_dir" config --format json)"
[[ "$example_config" == *'"mailbox-mirror": {'* && "$example_config" == *'"HOST1": "imap.source.example"'* ]] \
  || fail "single mailbox template does not configure the default service"
# Compose doubles dollars in its serialized configuration; the password stays literal.
[[ "$example_config" == *'"PASSWORD1": "fake $$literal #password"'* ]] \
  || fail "quoted example passwords must preserve dollar signs and hashes"
(
  set -a
  source "${example_dir}/.env"
  source "${repo_root}/docker/config.sh"
  mailbox_mirror_config_load
) || fail "minimal single mailbox template must pass runtime validation"

cp "${repo_root}/.env.multi-mailbox.example" "${example_dir}/.env"
example_services="$(docker compose --project-directory "$example_dir" config --services)"
[[ "$example_services" == *mailbox-mirror-a* && "$example_services" == *mailbox-mirror-b* && "$example_services" == *mailbox-mirror-c* ]] \
  || fail "multi-mailbox template must select its Compose file without -f"
[[ "$example_services" != *$'mailbox-mirror\n'* && "$example_services" != mailbox-mirror ]] \
  || fail "multi-mailbox template must not select the single mailbox service"
example_config="$(docker compose --project-directory "$example_dir" config --format json)"
[[ "$example_config" == *'"USER1": "source-a@example.com"'* && "$example_config" == *'"FOLDER_FILTER": "INBOX"'* && "$example_config" == *'"RUN_ON_STARTUP": "false"'* ]] \
  || fail "multi-mailbox template must preserve mailbox mapping and existing defaults"

echo "ok - Compose configuration contracts"
