#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/docker/config.sh"
source "${repo_root}/docker/folder-options.sh"

fail() {
  echo "not ok - $*" >&2
  exit 1
}

reset_options() {
  unset FOLDER_INCLUDE FOLDER_EXCLUDE FOLDER_MAP DESTINATION_PREFIX SYNC_MODE ALLOW_DELETIONS
}

assert_invalid() {
  if mailbox_folder_options_validate >/dev/null 2>&1; then
    fail "$*"
  fi
}

reset_options
mailbox_folder_options_validate
command_args=(imapsync)
mailbox_folder_options_append command_args
[[ "${#command_args[@]}" == 1 ]] || fail "defaults must preserve the existing command"

FOLDER_INCLUDE=$'INBOX\nSent Items\n\nProject [2026]'
FOLDER_EXCLUDE=$'^Trash$\n^Junk/'
FOLDER_MAP=$'Sent Items=Imported/Sent\nArchive=Old=Archive'
mailbox_folder_options_validate
mailbox_folder_options_append command_args
expected=(imapsync --folder INBOX --folder 'Sent Items' --folder 'Project [2026]' --exclude '^Trash$' --exclude '^Junk/' --f1f2 'Sent Items=Imported/Sent' --f1f2 'Archive=Old=Archive')
[[ "$(printf '%s\n' "${command_args[@]}")" == "$(printf '%s\n' "${expected[@]}")" ]] \
  || fail "folder names, regexes, and mappings must remain separate literal arguments"

for FOLDER_MAP in 'INBOX' '=Destination' 'Source=' $'INBOX=First\nINBOX=Second' $'Source=Destination\r'; do
  assert_invalid "malformed folder map accepted"
done
reset_options
SYNC_MODE=mirror
assert_invalid "mirror mode must require explicit deletion consent"
ALLOW_DELETIONS=true
mailbox_folder_options_validate
command_args=(imapsync)
mailbox_folder_options_append command_args
[[ "${command_args[*]}" == 'imapsync --delete2 --expunge2' ]] || fail "mirror mode must enable destination message deletions"
SYNC_MODE=unknown
assert_invalid "unknown sync mode accepted"
SYNC_MODE=additive
ALLOW_DELETIONS=yes
assert_invalid "invalid deletion boolean accepted"

reset_options
DESTINATION_PREFIX=$'Folder\n'
assert_invalid "multiline destination prefix accepted"
DESTINATION_PREFIX=$'Folder\r'
assert_invalid "carriage return in destination prefix accepted"

command -v perl >/dev/null || fail "perl is required to verify literal prefix transformations"
for DESTINATION_PREFIX in 'Source/' 'Name $1 @ARGV \E \L / [x] ; "test"/' 'x/;die "injected";#/' "Single'quote/"; do
  mailbox_folder_options_validate
  command_args=()
  mailbox_folder_options_append command_args
  [[ "${command_args[0]}" == --noautomap && "${command_args[1]}" == --regextrans2 ]] \
    || fail "prefix must disable automatic mappings that would bypass it"
  PREFIX_EXPECTED="$DESTINATION_PREFIX" perl -e '
    my $folder = "INBOX";
    my $expression = $ARGV[0];
    eval "\$folder =~ $expression; 1" or die $@;
    die "prefix was interpreted instead of preserved" unless $folder eq $ENV{PREFIX_EXPECTED} . "INBOX";
  ' "${command_args[2]}" || fail "destination prefix must stay literal"
done

echo "ok - folder selection and deletion modes"
