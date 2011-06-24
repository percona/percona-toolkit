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

use List::Util qw(sum);
use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf 127.0.0.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/before.sql');

# Ensure --probability works
$output = `$cmd --probability 0 -d test --chunk-size 4 | grep -v DATABASE`;
chomp $output;
my @chunks = $output =~ m/(\d+)\s+127\.0\.0\.1/g;
is(sum(@chunks), 0, 'Nothing with --probability 0!');

# Make sure that it actually checksumed tables and that sum(@chunks)
# isn't zero because no tables were checksumed.
is(
   scalar @chunks,
   6,
   'Checksummed the tables'
);
like(
   $output,
   qr/test\s+argtest\s+0\s+127.0.0.1\s+MyISAM\s+3\s+875b102e/,
   'It actually did something'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
