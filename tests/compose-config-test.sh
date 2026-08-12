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

echo "ok - Compose configuration contracts"
