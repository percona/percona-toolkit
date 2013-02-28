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

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;

require "$trunk/bin/pt-online-schema-change";
# Do this after requiring ptc, since it uses Mo
require VersionParser;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $node1 = $sb->get_dbh_for('node1');
my $node2 = $sb->get_dbh_for('node2');
my $node3 = $sb->get_dbh_for('node3');

if ( !$node1 ) {
   plan skip_all => 'Cannot connect to cluster node1';
}
elsif ( !$node2 ) {
   plan skip_all => 'Cannot connect to cluster node2';
}
elsif ( !$node3 ) {
   plan skip_all => 'Cannot connect to cluster node3';
}

my $db_flavor = VersionParser->new($node1)->flavor();
if ( $db_flavor !~ /XtraDB Cluster/ ) {
   plan skip_all => "PXC tests";
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $node1_dsn = $sb->dsn_for('node1');
my $output;
my $exit;
my $sample  = "t/pt-online-schema-change/samples/";

# #############################################################################
# Can't alter a MyISAM table.
# #############################################################################

$sb->load_file('node1', "$sample/basic_no_fks.sql");

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(
      "$node1_dsn,D=pt_osc,t=t",
      qw(--set-vars innodb_lock_wait_timeout=5),
      qw(--print --execute --alter ENGINE=InnoDB)) },
   stderr => 1,
);

ok(
   $exit,
   "Table is MyISAM: non-zero exit"
) or diag($output);

like(
   $output,
   qr/is a cluster node and the table is MyISAM/,
   "Table is MyISAM: error message"
);

# #############################################################################
# Can't alter a table converted to MyISAM.
# #############################################################################

$sb->load_file('node1', "$sample/basic_no_fks_innodb.sql");

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(
      "$node1_dsn,D=pt_osc,t=t",
      qw(--set-vars innodb_lock_wait_timeout=5),
      qw(--print --execute --alter ENGINE=MyISAM)) },
   stderr => 1,
);

ok(
   $exit,
   "Convert table to MyISAM: non-zero exit"
) or diag($output);

like(
   $output,
   qr/is a cluster node and the table is being converted to MyISAM/,
   "Convert table to MyISAM: error message"
);

# #############################################################################
# Require wsrep_OSU_method=TOI
# #############################################################################

$node1->do("SET GLOBAL wsrep_OSU_method='RSU'");

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(
      "$node1_dsn,D=pt_osc,t=t",
      qw(--set-vars innodb_lock_wait_timeout=5),
      qw(--print --execute --alter ENGINE=MyISAM)) },
   stderr => 1,
);

ok(
   $exit,
   "wsrep_OSU_method=RSU: non-zero exit"
) or diag($output);
print $output;
like(
   $output,
   qr/wsrep_OSU_method=TOI is required.+?currently set to RSU/,
   "wsrep_OSU_method=RSU: error message"
);

$node1->do("SET GLOBAL wsrep_OSU_method='TOI'");
is_deeply(
   $node1->selectrow_arrayref("SHOW VARIABLES LIKE 'wsrep_OSU_method'"),
   [qw(wsrep_OSU_method TOI)],
   "Restored wsrep_OSU_method=TOI"
) or BAIL_OUT("Failed to restore wsrep_OSU_method=TOI");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($node1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
