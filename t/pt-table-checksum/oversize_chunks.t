#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More skip_all => 'Finish updating oversize_chunks.t';

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";


my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3), '--max-load', ''); 
my $row;
my $output;

$sb->load_file('master', "t/pt-table-checksum/samples/oversize-chunks.sql");

# pt-table-checksum 2.0 isn't fooled as easily as 1.0 was.  This
# test results in:
#    Error checksumming table osc.t: Possible infinite loop detected!
#    The lower boundary for chunk 2 is <13, 13> and the lower boundary
#    for chunk 3 is also <13, 13>.  This usually happens when using a
#    non-unique single column index.  The current chunk index for table
#    osc.t is i which is not unique and covers 1 column.

ok(
   no_diff(
      sub { pt_table_checksum::main(@args,
         qw(-t osc.t --chunk-size 10)) },
      "t/pt-table-checksum/samples/oversize-chunks.txt",
   ),
   "Skip oversize chunk"
);

ok(
   no_diff(
      sub { pt_table_checksum::main(@args,
         qw(-t osc.t --chunk-size 10 --chunk-size-limit 0)) },
      "t/pt-table-checksum/samples/oversize-chunks-allowed.txt"
   ),
   "Allow oversize chunk"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
