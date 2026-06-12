#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

binmode(STDIN, ':utf8') or die "Can't binmode(STDIN, ':utf8'): $OS_ERROR";
binmode(STDOUT, ':utf8') or die "Can't binmode(STDOUT, ':utf8'): $OS_ERROR";

use strict;
use utf8;
use Encode qw(decode encode);
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1'); 
my $replica2_dbh = $sb->get_dbh_for('replica2'); 

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}
else {
   plan tests => 7;
}

my ($output, $status);
my @args = ('h=127.0.0.1,P=12346,u=msandbox,p=msandbox', '--databases=pt_ts', '--sync-to-source', '--execute');

# use lib/samples dir since the main change is in DSNParser
$sb->load_file('source', "t/pt-table-sync/samples/pt-2309.sql");

$sb->wait_for_replicas();

$replica1_dbh->do("DELETE FROM pt_ts.test_table LIMIT 1000");
$replica1_dbh->do("DELETE FROM pt_ts.test_table_char LIMIT 1000");
$replica1_dbh->do("FLUSH TABLES");

# 1
push(@args, ('--tables=test_table'));
$output = output(
   sub { pt_table_sync::main(@args) },
   stderr => 1,
);

unlike(
   $output,
   qr/Cannot nibble table/,
   'No "Cannot nibble table" error for binary data',
) or diag($output);

$sb->wait_for_replicas();

my $source_rows = $source_dbh->selectrow_arrayref("SELECT COUNT(*) FROM pt_ts.test_table");
my $replica_rows = $replica1_dbh->selectrow_arrayref("SELECT COUNT(*) FROM pt_ts.test_table");

is(
   $replica_rows->[0],
   $source_rows->[0],
   "Rows synced correctly for test_table"
) or diag($output);

is(
   pop(@args),
   "--tables=test_table",
   "test_table popped from the arguments array",
);

# 2
push(@args, ('--tables=test_table_char'));
$output = output(
   sub { pt_table_sync::main(@args) },
   stderr => 1,
);

unlike(
   $output,
   qr/Cannot nibble table/,
   'No "Cannot nibble table" error for UUID in CHAR column',
) or diag($output);

$sb->wait_for_replicas();

$source_rows = $source_dbh->selectrow_arrayref("SELECT COUNT(*) FROM pt_ts.test_table_char");
$replica_rows = $replica1_dbh->selectrow_arrayref("SELECT COUNT(*) FROM pt_ts.test_table_char");

is(
   $replica_rows->[0],
   $source_rows->[0],
   "Rows synced correctly for test_table_char"
) or diag($output);

is(
   pop(@args),
   "--tables=test_table_char",
   "test_table_char popped from the arguments array",
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
