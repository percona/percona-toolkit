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
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1'); 
my $slave2_dbh = $sb->get_dbh_for('slave2'); 

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}
else {
   plan tests => 3;
}


my ($output, $status);
my @args = ('h=127.0.0.1,P=12346,u=msandbox,p=msandbox,D=test,t=test2', '--sync-to-master', 
    '--chunk-size=1', '--hex-blob', '--execute');

# use lib/samples dir since the main change is in DSNParser
$sb->load_file('master', "t/pt-table-sync/samples/pt-2016.sql");

$sb->wait_for_slaves();

$slave1_dbh->do("UPDATE test.test2 SET col3='bbb'");
$slave1_dbh->do("FLUSH TABLES");

# 1
($output, $status) = full_output(
   sub { pt_table_sync::main(@args) },
);

is(
   $status,
   2,  # exit_status = 2 -> there were differences
   "PT-2016 table-sync CRC32 in key - Exit status",
);

# 2
my $want = {
  col1 => 1,
  col2 => 'aaa',
  col3 => 'aaa'
};
my $row = $slave1_dbh->selectrow_hashref("SELECT col1, col2, col3 FROM test.test2");
is_deeply(
    $row,
    $want,
    "PT-2016 table-sync CRC32 in key - Master was updated",
) or diag("Want '".($want||"")."', got '".($row->{col3}||"")."'");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
