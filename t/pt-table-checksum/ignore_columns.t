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
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
else {
   plan tests => 4;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($source_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my $output;

$sb->create_dbs($source_dbh, [qw(test)]);
$sb->load_file('source', 't/pt-table-checksum/samples/issue_94.sql');
$replica_dbh->do("update test.issue_94 set c=''");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d test --ignore-databases mysql -t issue_94)) },
   trf => sub { return PerconaTest::count_checksum_results(@_, 'DIFFS') },
);
is(
   $output,
   "1",
   "Diff when column not ignored"
) or diag($output);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d test -t issue_94),
      qw(--ignore-columns c)) },
   trf => sub { return PerconaTest::count_checksum_results(@_, 'DIFFS') },
);
is(
   $output,
   "0",
   "No diff when column ignored"
) or diag($output);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d test -t issue_94),
      qw(--ignore-columns c --explain)) },
);
unlike(
   $output,
   qr/`c`/,
   "Ignored column is not in checksum query"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
