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
use Time::HiRes qw(time);

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
use Data::Dumper;
require "$trunk/bin/pt-archiver";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $node1_dbh = $sb->get_dbh_for('node1');
my $node2_dbh = $sb->get_dbh_for('node2');
my $node3_dbh = $sb->get_dbh_for('node3');

if ( !$node1_dbh ) {
   plan skip_all => 'Cannot connect to cluster node1';
}
elsif ( !$node2_dbh ) {
   plan skip_all => 'Cannot connect to cluster node2';
}
elsif ( !$node3_dbh ) {
   plan skip_all => 'Cannot connect to cluster node3';
}
elsif ( !$sb->is_cluster_mode ) {
   plan skip_all => "PXC tests";
}

my $output;
my $count;
my $sql;
my $rows;
my $node1_cnf = $sb->config_file_for("node1");
my $node2_cnf = $sb->config_file_for("node2");
my @args = qw(--where 1=1);

$sb->create_dbs($node1_dbh, ['test']);

sub check_rows {
   my (%args) = @_;
   my @required_args = qw(name sql expect);
      foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($name, $sql, $expect) = @args{@required_args};

   $sb->wait_for_slaves;

   my $rows = $node1_dbh->selectall_arrayref($sql);
   is_deeply(
      $rows,
      $expect,
      "$name on node1"
   ) or diag(Dumper($rows));

   $rows = $node2_dbh->selectall_arrayref($sql);
   is_deeply(
      $rows,
      $expect,
      "$name on node2"
   ) or diag(Dumper($rows));

   $rows = $node3_dbh->selectall_arrayref($sql);
   is_deeply(
      $rows,
      $expect,
      "$name on node3"
   ) or diag(Dumper($rows));
}

# ###########################################################################
# Purge rows.
# ###########################################################################

$sb->load_file('node1', 't/pt-archiver/samples/tables1-4.sql');
$node1_dbh->do("INSERT INTO test.table_2 SELECT * FROM test.table_1");

# Since there's no auto-inc column, all rows should be purged on all nodes.
$output = output(
   sub {
      pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$node1_cnf",
         qw(--purge))
   },
   stderr => 1,
);

check_rows(
   name   => "Purged all rows",
   sql    => "SELECT * FROM test.table_1 ORDER BY a",
   expect => [],
);

# table_2 has an auto-inc, so all rows less the max auto-inc row
# should be purged on all nodes.  This is due to --[no]safe-auto-increment.
$output = output(
   sub {
      pt_archiver::main(@args, '--source', "D=test,t=table_2,F=$node1_cnf",
         qw(--purge))
   },
   stderr => 1,
);

check_rows(
   name   => "Purged rows less max auto-inc",
   sql    => "SELECT * FROM test.table_2 ORDER BY a",
   expect => [[qw(4 2 3), "\n"]],
);

# ###########################################################################
# Do not purge rows.
# ###########################################################################

$sb->load_file('node1', 't/pt-archiver/samples/tables1-4.sql');
my $expected_rows = $node1_dbh->selectall_arrayref(
   "SELECT * FROM test.table_1 ORDER BY a");

$output = output(
   sub {
      pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$node1_cnf",
         qw(--no-delete --purge))
   },
   stderr => 1,
);

check_rows(
   name   => "--no-delete left all rows",
   sql    => "SELECT * FROM test.table_1 ORDER BY a",
   expect => $expected_rows,
);

# #############################################################################
# Archive rows to another table
# #############################################################################

# Presume the previous test ^ left tables1-4.sql loaded and that $expect_rows
# is still the real, expected rows.

# Same node

$output = output(
   sub {
      pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$node1_cnf",
         qw(--dest t=table_2))
   },
   stderr => 1,
);

check_rows(
   name   => "Rows purged from table_1 (same node)",
   sql    => "SELECT * FROM test.table_1 ORDER BY a",
   expect => [],
);

check_rows(
   name   => "Rows archived to table_2 (same node)",
   sql    => "SELECT * FROM test.table_2 ORDER BY a",
   expect => $expected_rows,
);

# To another node

$sb->load_file('node1', 't/pt-archiver/samples/tables1-4.sql');
$expected_rows = $node1_dbh->selectall_arrayref(
   "SELECT * FROM test.table_1 ORDER BY a");

$output = output(
   sub {
      pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$node1_cnf",
         '--dest', "F=$node2_cnf,D=test,t=table_2")
   },
   stderr => 1,
);

check_rows(
   name   => "Rows purged from table_1 (cross-node)",
   sql    => "SELECT * FROM test.table_1 ORDER BY a",
   expect => [],
);

check_rows(
   name   => "Rows archived to table_2 (cross-node)",
   sql    => "SELECT * FROM test.table_2 ORDER BY a",
   expect => $expected_rows,
);

# #############################################################################
# --bulk-insert
# #############################################################################

# Same node

$sb->load_file('node1', "t/pt-archiver/samples/bulk_regular_insert.sql");
$expected_rows = $node1_dbh->selectall_arrayref(
   "SELECT * FROM bri.t ORDER BY id");
# The max auto-inc col won't be archived, so:
my $max_auto_inc_row = pop @$expected_rows;

output(
   sub {
      pt_archiver::main(@args, '--source', "F=$node1_cnf,D=bri,t=t,L=1",
         qw(--dest t=t_arch --bulk-insert --limit 3))
   },
   stderr => 1,
);

check_rows(
   name   => "--bulk-insert source table (same node)",
   sql    => "select * from bri.t order by id",
   expect => [ $max_auto_inc_row ],
);

check_rows(
   name   => "--bulk-insert dest table (same node)",
   sql    => "select * from bri.t_arch order by id",
   expect => $expected_rows,
);

# To another node

$sb->load_file('node1', "t/pt-archiver/samples/bulk_regular_insert.sql");

output(
   sub {
      pt_archiver::main(@args, '--source', "F=$node1_cnf,D=bri,t=t,L=1",
         '--dest', "F=$node2_cnf,t=t_arch", qw(--bulk-insert --limit 3))
   },
   stderr => 1,
);

check_rows(
   name   => "--bulk-insert source table (cross-node)",
   sql    => "select * from bri.t order by id",
   expect => [ $max_auto_inc_row ],
);

check_rows(
   name   => "--bulk-insert dest table (cross-node)",
   sql    => "select * from bri.t_arch order by id",
   expect => $expected_rows,
);


# #############################################################################
# --bulk-delete
# #############################################################################

# Same node

$sb->load_file('node2', 't/pt-archiver/samples/table5.sql');
$expected_rows = $node1_dbh->selectall_arrayref(
   "SELECT * FROM test.table_5 ORDER BY a,b,c,d");

$output = output(
   sub {
      pt_archiver::main(@args, '--source', "D=test,t=table_5,F=$node1_cnf",
         qw(--no-ascend --limit 50 --bulk-delete),
         qw(--statistics --dest t=table_5_dest))
   },
   stderr => 1,
);

check_rows(
   name   => "--bulk-delete source table (same node)",
   sql    => "select * from test.table_5",
   expect => [],
);

check_rows(
   name   => "--bulk-delete dest table (same node)",
   sql    => "select * from test.table_5_dest order by a,b,c,d",
   expect => $expected_rows,
);

# To another node

$sb->load_file('node2', 't/pt-archiver/samples/table5.sql');

$output = output(
   sub {
      pt_archiver::main(@args, '--source', "D=test,t=table_5,F=$node1_cnf",
         qw(--no-ascend --limit 50 --bulk-delete),
         qw(--statistics), '--dest', "F=$node2_cnf,t=table_5_dest")
   },
   stderr => 1,
);

check_rows(
   name   => "--bulk-delete source table (cross-node)",
   sql    => "select * from test.table_5",
   expect => [],
);

check_rows(
   name   => "--bulk-delete dest table (cross-node)",
   sql    => "select * from test.table_5_dest order by a,b,c,d",
   expect => $expected_rows,
);

# #############################################################################
# Repeat some of the above tests with MyISAM.
# #############################################################################

$sb->load_file('node1', 't/pt-archiver/samples/table14.sql');
$expected_rows = $node1_dbh->selectall_arrayref(
   "SELECT * FROM test.table_1 ORDER BY a");
$node1_dbh->do("INSERT INTO test.table_2 SELECT * FROM test.table_1");

# Since there's no auto-inc column, all rows should be purged on all nodes.
$output = output(
   sub {
      pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$node1_cnf",
         qw(--purge))
   },
   stderr => 1,
);

check_rows(
   name   => "MyISAM: Purged all rows",
   sql    => "SELECT * FROM test.table_1 ORDER BY a",
   expect => [],
);


# table_2 has an auto-inc, so all rows less the max auto-inc row
# should be purged on all nodes.  This is due to --[no]safe-auto-increment.
$output = output(
   sub {
      pt_archiver::main(@args, '--source', "D=test,t=table_2,F=$node1_cnf",
         qw(--purge))
   },
   stderr => 1,
);

check_rows(
   name   => "MyISAM: Purged rows less max auto-inc",
   sql    => "SELECT * FROM test.table_2 ORDER BY a",
   expect => [[qw(4 2 3), "\n"]],
);

# Archive rows to another MyISAM table.

# Same node
$sb->load_file('node1', 't/pt-archiver/samples/table14.sql');
$output = output(
   sub {
      pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$node1_cnf",
         qw(--dest t=table_2))
   },
   stderr => 1,
);

check_rows(
   name   => "MyISAM: Rows purged from table_1 (same node)",
   sql    => "SELECT * FROM test.table_1 ORDER BY a",
   expect => [],
);

check_rows(
   name   => "MyISAM: Rows archived to table_2 (same node)",
   sql    => "SELECT * FROM test.table_2 ORDER BY a",
   expect => $expected_rows,
);

# To another node
$sb->load_file('node1', 't/pt-archiver/samples/table14.sql');

$output = output(
   sub {
      pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$node1_cnf",
         '--dest', "F=$node2_cnf,D=test,t=table_2")
   },
   stderr => 1,
);

check_rows(
   name   => "MyISAM: Rows purged from table_1 (cross-node)",
   sql    => "SELECT * FROM test.table_1 ORDER BY a",
   expect => [],
);

check_rows(
   name   => "MyISAM: Rows archived to table_2 (cross-node)",
   sql    => "SELECT * FROM test.table_2 ORDER BY a",
   expect => $expected_rows,
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($node1_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
