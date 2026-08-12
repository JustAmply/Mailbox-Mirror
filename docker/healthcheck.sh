#!/usr/bin/env bash
set -euo pipefail

source /usr/local/lib/mailbox-mirror/config.sh
source /usr/local/lib/mailbox-mirror/sync-job-state.sh
mailbox_mirror_config_load
sync_job_state_check_health
