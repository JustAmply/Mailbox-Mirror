#!/usr/bin/env bash
set -euo pipefail

# Report only known operational fields; never serialize the runtime environment.
exec perl -MJSON::PP -e '
  use strict;
  use warnings;
  my $directory = shift;
  my %status;
  for my $field (qw(last_status container_started_at last_attempt_at last_finished_at
      last_success_at last_dry_run_at last_duration_seconds last_exit_code
      consecutive_failures consecutive_skips last_messages_transferred active_pid)) {
    my $value;
    if (open my $file, "<", "$directory/$field") {
      $value = <$file>;
      close $file;
      chomp $value if defined $value;
    }
    if ($field ne "last_status") {
      $value = defined($value) && $value =~ /^\d+$/ ? 0 + $value : undef;
    }
    $status{$field} = $value;
  }
  print JSON::PP->new->canonical->pretty->encode(\%status);
' "${SYNC_JOB_STATE_DIR:-/var/lib/imapsync}"
