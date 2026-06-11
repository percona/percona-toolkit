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
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
else {
   plan tests => 7;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($source_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my $output;

$sb->load_file('source', "t/pt-table-checksum/samples/float_precision.sql");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t float_precision.t --explain)) },
);

like(
   $output,
   qr/^-- float_precision.t/m,
   "Got output"
);

unlike(
   $output,
   qr/ROUND\(`a`/,
   "No --float-precision, no rounding"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t float_precision.t --explain),
      qw(--float-precision 3)) },
);

like(
   $output,
   qr/^-- float_precision.t/m,
   "Got output"
);

like(
   $output,
   qr/ROUND\(`a`, 3/,
   'Column a is rounded'
);

like(
   $output,
   qr/ROUND\(`b`, 3/,
   'Column b is rounded'
);

like(
   $output,
   qr/ISNULL\(`b`\)/,
   'Column b is not rounded inside ISNULL'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
