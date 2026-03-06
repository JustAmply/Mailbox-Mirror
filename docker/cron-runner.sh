#!/usr/bin/env bash
set -euo pipefail

log_file="/var/log/imapsync.log"
max_log_size_mb="${MAX_LOG_SIZE_MB:-10}"

if [[ -f "$log_file" ]]; then
  current_size_bytes=$(wc -c < "$log_file")
  max_size_bytes=$((max_log_size_mb * 1024 * 1024))
  if (( current_size_bytes >= max_size_bytes )); then
    mv "$log_file" "${log_file}.1"
  fi
fi

touch "$log_file"
exec >> "$log_file" 2>&1

source /etc/imapsync.env
exec /usr/local/bin/run-imapsync.sh
