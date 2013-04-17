#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
require "$trunk/bin/pt-table-checksum";

my $output;

# Calling the tool pt_table_checksum::main() doesn't work when we're
# dealing with cmd line option error and --help because OptionParser
# exits on such things which would cause this test to exit too.

# ############################################################################
# Check default values for some options to ensure something wasn't
# changed accidentally.  A lot of tests rely on these defaults, so
# if they change, it can have weird side-effects.
# ############################################################################
$output = `$trunk/bin/pt-table-checksum h=127.1 --help`;

like(
   $output,
   qr/^  --check-replication-filters\s+TRUE$/m,
   "Default --check-replication-filters=TRUE"
);

like(
   $output,
   qr/^  --create-replicate-table\s+TRUE$/m,
   "Default --create-replicate-table=TRUE"
);

like(
   $output,
   qr/^  --empty-replicate-table\s+TRUE$/m,
   "Default --empty-replicate-table=TRUE"
);

like(
   $output,
   qr/^  --explain\s+0$/m,
   "Default --explain=0"
);

like(
   $output,
   qr/^  --host\s+localhost$/m,
   "Default --host=localhost"
);

#like(
#   $output,
#   qr/^  --lock-wait-timeout\s+1$/m,
#   "Default --lock-wait-timeout=1"
#);

like(
   $output,
   qr/^  --max-lag\s+1$/m,
   "Default --max-lag=1"
);

like(
   $output,
   qr/^  --quiet\s+0$/m,
   "Default --quiet=0"
);

like(
   $output,
   qr/^  --replicate-check-only\s+FALSE$/m,
   "Default --replicate-check-only=FALSE"
);

like(
   $output,
   qr/^  --replicate\s+percona\.checksums$/m,
   "Default --replicate=percona.checksums"
);

like(
   $output,
   qr/^  --replicate-check\s+TRUE$/m,
   "Default --replicate-check=TRUE"
);

like(
   $output,
   qr/^\s+--recursion-method=a/m,
   "--recursion-method is an array"
);

like(
   $output,
   qr/^\s+--recursion-method\s+processlist,hosts/m,
   "Default --recursion-method is processlist,hosts"
);

# ############################################################################
# Check opts that disable other opts.
# ############################################################################
$output = `$trunk/bin/pt-table-checksum h=127.1 --help --explain`;
like(
   $output,
   qr/^  --empty-replicate-table\s+FALSE$/m,
   "--explain disables --empty-replicate-table"
);

$output = `$trunk/bin/pt-table-checksum h=127.1 --help --resume`;
like(
   $output,
   qr/^  --empty-replicate-table\s+FALSE$/m,
   "--resume disables --empty-replicate-table"
);

$output = `$trunk/bin/pt-table-checksum h=127.1 --help --quiet`;
like(
   $output,
   qr/^  --progress\s+\(No value\)$/m,
   "--quiet disables --progress"
);

$output = `$trunk/bin/pt-table-checksum --help --chunk-size 500`;
like(
   $output,
   qr/^  --chunk-time\s+0$/m,
   "--chunk-size sets --chunk-time=0"
);

# ############################################################################
# Only 1 DSN should be allowed on the command line; no extra args.
# ############################################################################
$output = `$trunk/bin/pt-table-checksum h=127.1 h=host1 h=host2`;
like(
   $output,
   qr/More than one host specified; only one allowed/,
   "Only one DSN allowed on the command line"
);

# ############################################################################
# --replicate table must be db-qualified.
# ############################################################################
$output = `$trunk/bin/pt-table-checksum h=127.1 --replicate checksums`;
like(
   $output,
   qr/--replicate table must be database-qualified/,
   "--replicate table must be database-qualified"
);

# ############################################################################
# --chunk-size-limit >= 1 or 0
# ############################################################################
$output = `$trunk/bin/pt-table-checksum --chunk-size-limit 0.999`;
like(
   $output,
   qr/chunk-size-limit must be >= 1 or 0 to disable/,
   "--chunk-size-limit must be >= 1 or 0"
);

# #############################################################################
# --max-load
# #############################################################################

$output = `$trunk/bin/pt-table-checksum h=127.1,P=12345 --max-load 100`;
like(
   $output,
   qr/Invalid --max-load/,
   "Validates --max-load"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
