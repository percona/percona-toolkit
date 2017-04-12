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

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir /;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

if ( !$sb->is_cluster_mode ) {
   plan skip_all => 'Only for PXC',
}

my ($master_dbh, $master_dsn) = $sb->start_sandbox(
   server => 'cmaster',
   type   => 'master',
   env    => q/FORK="pxc" BINLOG_FORMAT="ROW"/,
);

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# This is the same test we have for bug-1613915 but using DATA-DIR
$sb->load_file('cmaster', "$sample/bug-1613915.sql");
my $dir = tempdir( CLEANUP => 1 );
$output = output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=o1",
         '--execute', 
         '--alter', "ADD COLUMN c INT",
         '--chunk-size', '10',
         '--data-dir', $dir,
         ),
      },
);

like(
      $output,
      qr/Successfully altered/s,
      "bug-1613915 enum field in primary key",
);

my $rows = $master_dbh->selectrow_arrayref(
   "SELECT COUNT(*) FROM test.o1");
is(
   $rows->[0],
   100,
   "bug-1613915 correct rows count"
) or diag(Dumper($rows));

$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->stop_sandbox(qw(cmaster)); 
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
