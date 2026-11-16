#!/usr/bin/env bash

mailbox_folder_options_validate() {
  case "${SYNC_MODE:-additive}" in
    additive|mirror) ;;
    *)
      mailbox_mirror_config_error "Invalid SYNC_MODE (expected additive or mirror)"
      return 1
      ;;
  esac
  case "${ALLOW_DELETIONS:-false}" in
    true|false) ;;
    *)
      mailbox_mirror_config_error "Invalid ALLOW_DELETIONS (expected true or false)"
      return 1
      ;;
  esac
  if [[ "${SYNC_MODE:-additive}" == mirror && "${ALLOW_DELETIONS:-false}" != true ]]; then
    mailbox_mirror_config_error "SYNC_MODE=mirror requires ALLOW_DELETIONS=true"
    return 1
  fi
  if [[ "${DESTINATION_PREFIX:-}" == *$'\n'* || "${DESTINATION_PREFIX:-}" == *$'\r'* ]]; then
    mailbox_mirror_config_error "DESTINATION_PREFIX must not contain line breaks"
    return 1
  fi

  local mapping source destination mapped_sources=$'\n'
  while IFS= read -r mapping; do
    [[ -n "$mapping" ]] || continue
    source="${mapping%%=*}"
    destination="${mapping#*=}"
    if [[ "$mapping" != *=* || -z "$source" || -z "$destination" || "$mapping" == *$'\r'* ]]; then
      mailbox_mirror_config_error "Invalid FOLDER_MAP entry (expected source=destination with nonempty names)"
      return 1
    fi
    if [[ "$mapped_sources" == *$'\n'"$source"$'\n'* ]]; then
      mailbox_mirror_config_error "FOLDER_MAP must not map the same source folder more than once"
      return 1
    fi
    mapped_sources+="${source}"$'\n'
  done <<< "${FOLDER_MAP:-}"
}

mailbox_folder_options_append() {
  local -n folder_options_command_ref="$1"
  local value prefix

  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    folder_options_command_ref+=(--folder "$value")
  done <<< "${FOLDER_INCLUDE:-}"
  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    folder_options_command_ref+=(--exclude "$value")
  done <<< "${FOLDER_EXCLUDE:-}"
  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    folder_options_command_ref+=(--f1f2 "$value")
  done <<< "${FOLDER_MAP:-}"

  if [[ -n "${DESTINATION_PREFIX:-}" ]]; then
    # The replacement is evaluated by Perl: keep user text literal, including
    # backslashes, interpolation markers, and the substitution delimiter.
    prefix="${DESTINATION_PREFIX//\\/\\\\}"
    prefix="${prefix//\$/\\\$}"
    prefix="${prefix//@/\\@}"
    prefix="${prefix//\//\\/}"
    # Automatic special-folder mappings bypass regextrans2 in imapsync.
    folder_options_command_ref+=(--noautomap --regextrans2 "s/^/${prefix}/")
  fi
  if [[ "${SYNC_MODE:-additive}" == mirror ]]; then
    folder_options_command_ref+=(--delete2 --expunge2)
  fi
}
