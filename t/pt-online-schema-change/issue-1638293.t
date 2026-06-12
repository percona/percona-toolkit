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

my ($source_dbh, $source_dsn) = $sb->start_sandbox(
   server => 'csource',
   type   => 'source',
   env    => q/BINLOG_FORMAT="ROW"/,
);

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# This is the same test we have for bug-1613915 but using DATA-DIR
$sb->load_file('csource', "$sample/bug-1613915.sql");
my $dir = tempdir( CLEANUP => 1 );
my $csource_port=$sb->port_for('csource');

if ($sandbox_version ge '8.0') {
    diag(`/tmp/$csource_port/stop >/dev/null`);
	diag(`echo "innodb_directories='$dir'" >> /tmp/$csource_port/my.sandbox.cnf`);
    diag(`/tmp/$csource_port/start > /dev/null`);
}

$source_dbh = $sb->get_dbh_for('csource');

$output = output(
   sub { pt_online_schema_change::main(@args, "$source_dsn,D=test,t=o1",
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

my $rows = $source_dbh->selectrow_arrayref(
   "SELECT COUNT(*) FROM test.o1");
is(
   $rows->[0],
   100,
   "bug-1613915 correct rows count"
) or diag(Dumper($rows));

$source_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
$sb->stop_sandbox(qw(csource)); 
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
