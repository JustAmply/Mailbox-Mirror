#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for script in docker/*.sh tests/*.sh; do
  bash -n "$script"
done
echo "ok - shell syntax"

if ! git check-ignore --quiet .env; then
  echo "not ok - .env must be ignored because it contains mailbox credentials" >&2
  exit 1
fi
echo "ok - local credentials ignored"

bash tests/mailbox-run-test.sh
bash tests/config-test.sh
bash tests/sync-job-state-test.sh
bash tests/compose-config-test.sh
