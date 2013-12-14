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
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}

my $master_dsn = $sb->dsn_for('master');
my $slave1_dsn = $sb->dsn_for('slave1');

# #############################################################################
# --[no]check-child-tables
# pt-table-sync deletes child table rows Edit
# https://bugs.launchpad.net/percona-toolkit/+bug/1223458
# #############################################################################

$sb->load_file('master', 't/pt-table-sync/samples/on_del_cas.sql');

$master_dbh->do("INSERT INTO on_del_cas.parent VALUES (1), (2)");
$master_dbh->do("INSERT INTO on_del_cas.child1 VALUES (null, 1)");
$master_dbh->do("INSERT INTO on_del_cas.child2 VALUES (null, 1)");
$sb->wait_for_slaves();

$output = output(
   sub {
      pt_table_sync::main($slave1_dsn, qw(--sync-to-master),
         qw(--execute -d on_del_cas))
   },
   stderr => 1,
);

like(
   $output,
   qr/on on_del_cas.parent can adversely affect child table `on_del_cas`.`child2` because it has an ON DELETE CASCADE/,
   "check-child-tables: error message"
);

my $rows = $slave_dbh->selectall_arrayref("select * from on_del_cas.child2");
is_deeply(
   $rows,
   [ [1,1] ],
   "check-child-tables: child2 row not deleted"
) or diag(Dumper($rows));

$output = output(
   sub {
      pt_table_sync::main($slave1_dsn, qw(--sync-to-master),
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
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
