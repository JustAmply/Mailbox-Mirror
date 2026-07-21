#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for script in docker/*.sh tests/*.sh; do
  bash -n "$script"
done
echo "ok - shell syntax"

bash tests/mailbox-run-test.sh
bash tests/compose-config-test.sh
