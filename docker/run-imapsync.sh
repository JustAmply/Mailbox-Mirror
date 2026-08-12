#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -Iseconds)] $*"
}

source /usr/local/lib/mailbox-mirror/mailbox-run.sh

mailbox_run_execute
