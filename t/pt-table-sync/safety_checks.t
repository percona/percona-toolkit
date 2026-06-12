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
require "$trunk/bin/pt-table-sync";

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh  = $sb->get_dbh_for('replica1');
my $replica2_dbh  = $sb->get_dbh_for('replica2');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}

my $source_dsn = $sb->dsn_for('source');
my $replica1_dsn = $sb->dsn_for('replica1');

# #############################################################################
# --[no]check-child-tables
# pt-table-sync deletes child table rows Edit
# https://bugs.launchpad.net/percona-toolkit/+bug/1223458
# #############################################################################

$sb->load_file('source', 't/pt-table-sync/samples/on_del_cas.sql');

$source_dbh->do("INSERT INTO on_del_cas.parent VALUES (1), (2)");
$source_dbh->do("INSERT INTO on_del_cas.child1 VALUES (null, 1)");
$source_dbh->do("INSERT INTO on_del_cas.child2 VALUES (null, 1)");
$sb->wait_for_replicas();

$output = output(
   sub {
      pt_table_sync::main($replica1_dsn, qw(--sync-to-source),
         qw(--execute -d on_del_cas))
   },
   stderr => 1,
);

like(
   $output,
   qr/on on_del_cas.parent can adversely affect child table `on_del_cas`.`child2` because it has an ON DELETE CASCADE/,
   "check-child-tables: error message"
);

my $rows = $replica1_dbh->selectall_arrayref("select * from on_del_cas.child2");
is_deeply(
   $rows,
   [ [1,1] ],
   "check-child-tables: child2 row not deleted"
) or diag(Dumper($rows));

$output = output(
   sub {
      pt_table_sync::main($replica1_dsn, qw(--sync-to-source),
         qw(--print -d on_del_cas))
   },
   stderr => 1,
);

unlike(
   $output,
   qr/on on_del_cas.parent can adversely affect child table `on_del_cas`.`child2` because it has an ON DELETE CASCADE/,
   "check-child-tables: no error message with --print"
);

# #############################################################################
# --[no]check-source
# #############################################################################
# Connecting replica with wrong user name
$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("CHANGE ${source_change} TO ${source_name}_port=12347, ${source_name}_user='does_not_exist'");
$replica1_dbh->do("START ${replica_name}");

$output = output(
   sub {
      pt_table_sync::main($replica1_dsn, qw(--sync-to-source),
         qw(--execute -d on_del_cas --wait 0))
   },
   stderr => 1,
);

like(
   $output,
   qr/The server specified as a source has no connected replicas/,
   "Error when --check-source is enabled (default)"
) or diag($output);

$output = output(
   sub {
      pt_table_sync::main($replica1_dsn, qw(--sync-to-source),
         qw(--execute -d on_del_cas --wait 0 --no-check-source))
   },
   stderr => 1,
);

unlike(
   $output,
   qr/The server specified as a source has no connected replicas/,
   "No wrong source error when --check-source is disabled"
) or diag($output);

unlike(
   $output,
   qr/Option --\[no\]check-master is deprecated and will be removed in future versions./,
   'Deprecation warning not printed when option --no-check-source provided'
) or diag($output);

# Legacy option
$output = output(
   sub {
      pt_table_sync::main($replica1_dsn, qw(--sync-to-source),
         qw(--execute -d on_del_cas --wait 0 --no-check-master))
   },
   stderr => 1,
);

unlike(
   $output,
   qr/The server specified as a source has no connected replicas/,
   "No wrong source error when --check-master is disabled"
) or diag($output);

like(
   $output,
   qr/Option --\[no\]check-master is deprecated and will be removed in future versions./,
   'Deprecation warning printed when option --no-check-master provided'
) or diag($output);

$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("CHANGE ${source_change} TO ${source_name}_port=12345, ${source_name}_user='msandbox'");
$source_dbh->do("RESET ${source_reset}");
$replica1_dbh->do("RESET ${replica_name}");
$replica1_dbh->do("START ${replica_name}");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
$sb->wait_for_replicas();
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
