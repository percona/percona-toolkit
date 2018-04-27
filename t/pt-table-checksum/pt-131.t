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
use SqlModes;
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
my $sb_version = VersionParser->new($dbh);
my $rows = $dbh->selectall_hashref("SHOW VARIABLES LIKE '%version%'", ['variable_name']);

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
} elsif ( $sb_version < '5.7.21' || !($rows->{version_comment}->{value} =~ m/percona server/i) ) {
   plan skip_all => 'This test file needs Percona Server 5.7.21.21+';
} else {
   plan tests => 3;
}

eval {
      $dbh->selectrow_arrayref('SELECT @@query_response_time_session_stats' );
};
if ($EVAL_ERROR) {
    $sb->load_file('master', 't/pt-table-checksum/samples/pt-131.sql');
}
# The sandbox servers run with lock_wait_timeout=3 and it is not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = $sb->dsn_for('master');
my $output;
my $exit_status;
$ENV{PTDEBUG} = 1;

my $cmd ="PTDEBUG=1 $trunk/bin/pt-table-checksum $master_dsn --disable-qrt-plugin 2>&1";

$output = `$cmd`;
like (
    $output,
    qr/Restoring qrt plugin state/,
    "QRT plugin status has been restored",
);

like (
    $output,
    qr/Disabling qrt plugin on master server/,
    "QRT plugin has been disabled",
);
delete $ENV{PTDEBUG};

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
