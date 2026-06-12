#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;
use threads::shared;

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

if ( $sandbox_version ge '8.4') {
   plan skip_all => 'PXC 8.4 does not exist yet';
}

our ($source_dbh, $source_dsn) = $sb->start_sandbox(
   server => 'source',
   type   => 'source',
   env    => q/FORK="pxc" BINLOG_FORMAT="ROW"/,
);

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

plan tests => 2;

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

$sb->load_file('source', "$sample/issue-1646713.sql");
my $num_rows = 1000;
my $source_port = 12345;

$source_dbh->do("FLUSH TABLES");
$sb->wait_for_replicas();

sub start_thread {
   my ($dsn_opts, $sleep_time) = @_;
   my $dp = new DSNParser(opts=>$dsn_opts);
   my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
   my $dbh = $sb->get_dbh_for('source');
   diag("Thread started: Sleeping $sleep_time seconds before updating the PK field for row with id=1 in test.sbtest");
   # We need to lock the tables to prevent osc to really start before we are able to write the row to the table
   $dbh->do("LOCK TABLES `test`.`o1` WRITE");
   select(undef, undef, undef, $sleep_time);
   $dbh->do("UPDATE `test`.`o1` SET id=0 WHERE id=1");
   $dbh->do("UNLOCK TABLES");
   diag("Row updated");
}
my $thr = threads->create('start_thread', $dsn_opts, 0.50);
$thr->detach();
threads->yield();


diag("Starting osc. A row will be updated in a different thread.");
my $dir = tempdir( CLEANUP => 1 );
$output = output(
   sub { pt_online_schema_change::main(@args, "$source_dsn,D=test,t=o1",
         '--execute', 
         '--alter', "ADD COLUMN c INT",
         '--chunk-size', '1',
         ),
      },
);
diag($output);

like(
      $output,
      qr/Successfully altered/s,
      "bug-1646713 duplicate rows in _t_new for UPDATE t set pk=0 where pk=1",
);

my $rows = $source_dbh->selectrow_arrayref(
   "SELECT COUNT(*) FROM `test`.`o1` WHERE id=0");
is(
   $rows->[0],
   1,
   "bug-1646713 correct value after updating the PK"
) or diag(Dumper($rows));

threads->exit();

$source_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
$sb->stop_sandbox(qw(source)); 
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
