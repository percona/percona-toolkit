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
# Issue 410: mk-table-sync doesn't have --float-precision
# #############################################################################

$sb->create_dbs($master_dbh, ['test']);
$master_dbh->do('create table test.fl (id int not null primary key, f float(12,10), d double)');
$master_dbh->do('insert into test.fl values (1, 1.0000012, 2.0000012)');
$sb->wait_for_slaves();
$slave_dbh->do('update test.fl set d = 2.0000013 where id = 1');

# The columns really are different at this point so we should
# get a REPLACE without using --float-precision.
$output = `$trunk/bin/pt-table-sync --sync-to-master h=127.1,P=12346,u=msandbox,p=msandbox,D=test,t=fl --print 2>&1`;
$output = remove_traces($output);
is(
   $output,
   "REPLACE INTO `test`.`fl`(`id`, `f`, `d`) VALUES ('1', 1.0000011921, 2.0000012);
",
   'No --float-precision so double col diff at high precision (issue 410)'
);

# Now use --float-precision to roundoff the differing columns.
# We have 2.0000012
#     vs. 2.0000013, so if we round at 6 places, they should be the same.
$output = `$trunk/bin/pt-table-sync --sync-to-master h=127.1,P=12346,u=msandbox,p=msandbox,D=test,t=fl --print --float-precision 6 2>&1`;
is(
   $output,
   '',
   '--float-precision so no more diff (issue 410)'
);

# #############################################################################
# pt-table-sync quotes floats, prevents syncing
# https://bugs.launchpad.net/percona-toolkit/+bug/1229861
# #############################################################################

$sb->load_file('master', "t/pt-table-sync/samples/sync-float.sql");
$slave_dbh->do("INSERT INTO sync_float_1229861.t (`c1`, `c2`, `c3`, `snrmin`, `snrmax`, `snravg`) VALUES (1,1,1,29.5,33.5,31.6)");

$output = output(sub {
      pt_table_sync::main(
         "$master_dsn,D=sync_float_1229861,t=t",
         "$slave1_dsn",
         qw(--no-check-slave --print --execute))
   },
   stderr => 1,
);

my $rows = $slave_dbh->selectall_arrayref("SELECT * FROM sync_float_1229861.t");
is_deeply(
   $rows,
   [],
   "Sync rows with float values (bug 1229861)"
) or diag(Dumper($rows), $output);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
