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

use PerconaTest;
use Sandbox;
use Data::Dumper;
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $node1 = $sb->get_dbh_for('node1');
my $db_flavor = VersionParser->new($node1)->flavor();

if ( $db_flavor !~ /XtraDB Cluster/ ) {
   plan skip_all => "PXC tests";
}

my $c = $sb->start_cluster(
   nodes => [qw(node4 node5)],
   env   => q/CLUSTER_NAME="pt_archiver_cluster"/,
);

my $node4_dbh = $c->{node4}->{dbh};
my $node5_dbh = $c->{node5}->{dbh};

# Set this up so ->wait_for_slaves works
$node4_dbh->do("CREATE DATABASE IF NOT EXISTS percona_test");
$node4_dbh->do("CREATE TABLE IF NOT EXISTS percona_test.sentinel(id int primary key, ping varchar(64) not null default '')");
my ($ping) = $node4_dbh->selectrow_array("SELECT MD5(RAND())");
$node4_dbh->do("INSERT INTO percona_test.sentinel(id, ping) values(1, '$ping') ON DUPLICATE KEY UPDATE ping='$ping'");
sleep 1 until eval { $node5_dbh->selectrow_array("SELECT * FROM percona_test.sentinel") };

my $output;
my $count;
my $sql;
my $cnf  = $sb->config_file_for("node4");
my @args = qw(--where 1=1);

$sb->create_dbs($node4_dbh, ['test']);

# ###########################################################################
# These are roughly the same tests as basics.t, but we also check that the
# other ndoes got the right data.
# ###########################################################################

# Test --why-quit and --statistics output
$sb->load_file('node4', 't/pt-archiver/samples/tables1-4.sql');
$sb->wait_for_slaves(master => 'node4', slave => 'node5');
$output = output(sub {pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$cnf", qw(--purge --why-quit --statistics)) });
like($output, qr/Started at \d/, 'Start timestamp');
like($output, qr/Source:/, 'source');
like($output, qr/SELECT 4\nINSERT 0\nDELETE 4\n/, 'row counts');
like($output, qr/Exiting because there are no more rows/, 'Exit reason');

$sql = "SELECT * FROM test.table_1";
$sb->wait_for_slaves(master => 'node4', slave => 'node5');
my ($m, $n);
is_deeply(
   $m = $node4_dbh->selectall_arrayref($sql),
   $n = $node5_dbh->selectall_arrayref($sql),
   "Node4 & Node5 remain the same after --purge"
);

# Test --no-delete.
$sb->load_file('node4', 't/pt-archiver/samples/tables1-4.sql');
output(sub {pt_archiver::main(@args, qw(--no-delete --purge --source), "D=test,t=table_1,F=$cnf") });
$sb->wait_for_slaves(master => 'node4', slave => 'node5');
is_deeply(
   $node4_dbh->selectall_arrayref($sql),
   $node5_dbh->selectall_arrayref($sql),
   "Node4 & Node5 remain the same after --dest"
);

# --dest
$sb->load_file('node4', 't/pt-archiver/samples/tables1-4.sql');
output(sub {pt_archiver::main(@args, qw(--statistics --source), "D=test,t=table_1,F=$cnf", qw(--dest t=table_2)) });
$sb->wait_for_slaves(master => 'node4', slave => 'node5');
$sql = "SELECT * FROM test.table_1, test.table_2";
is_deeply(
   $node4_dbh->selectall_arrayref($sql),
   $node5_dbh->selectall_arrayref($sql),
   "Node4 & Node5 remain the same after --dest"
);

# #############################################################################
# Bug 903387: pt-archiver doesn't honor b=1 flag to create SQL_LOG_BIN statement
# #############################################################################
SKIP: {
   $sb->load_file('node4', "t/pt-archiver/samples/bulk_regular_insert.sql");
   $sb->wait_for_slaves(master => 'node4', slave => 'node5');

   my $original_rows  = $node5_dbh->selectall_arrayref("SELECT * FROM bri.t ORDER BY id");
   my $original_no_id = $node5_dbh->selectall_arrayref("SELECT c,t FROM bri.t ORDER BY id");
   is_deeply(
      $original_no_id,
      [
         ['aa', '11:11:11'],
         ['bb', '11:11:12'],
         ['cc', '11:11:13'],
         ['dd', '11:11:14'],
         ['ee', '11:11:15'],
         ['ff', '11:11:16'],
         ['gg', '11:11:17'],
         ['hh', '11:11:18'],
         ['ii', '11:11:19'],
         ['jj', '11:11:10'],
      ],
      "Bug 903387: node5 has rows"
   );

   $output = output(
      sub { pt_archiver::main(
         '--source', "D=bri,L=1,t=t,F=$cnf,b=1",
         '--dest',   "D=bri,t=t_arch",
         qw(--where 1=1 --replace --commit-each --bulk-insert --bulk-delete),
         qw(--limit 10)) },
   );

   $sb->wait_for_slaves(master => 'node4', slave => 'node5');
   
   my $rows = $node4_dbh->selectall_arrayref("SELECT c,t FROM bri.t ORDER BY id");
   is_deeply(
      $rows,
      [
         ['jj', '11:11:10'],
      ],
      "Bug 903387: rows deleted on node4"
   ) or diag(Dumper($rows));

   $rows = $node5_dbh->selectall_arrayref("SELECT * FROM bri.t ORDER BY id");
   is_deeply(
      $rows,
      $original_rows,
      "Bug 903387: node5 still has rows"
   ) or diag(Dumper($rows));

   $sql = "SELECT * FROM bri.t_arch ORDER BY id";
   is_deeply(
      $node5_dbh->selectall_arrayref($sql),
      $node4_dbh->selectall_arrayref($sql),
      "Bug 903387: node5 has t_arch"
   );

   $sb->load_file('node4', "t/pt-archiver/samples/bulk_regular_insert.sql");
   $sb->wait_for_slaves(master => 'node4', slave => 'node5');
   output(
      sub { pt_archiver::main(
         '--source', "D=bri,L=1,t=t,F=$cnf,b=1",
         '--dest',   "D=bri,t=t_arch,b=1",
         qw(--where 1=1 --replace --commit-each --bulk-insert --bulk-delete),
         qw(--limit 10)) },
   );

   is_deeply(
      $node5_dbh->selectall_arrayref("SELECT * FROM bri.t_arch ORDER BY id"),
      [],
      "Bug 903387: ...unless b=1 was also specified for --dest"
   );
}

# #############################################################################
# Test --bulk-insert
# #############################################################################

$sb->load_file('node4', "t/pt-archiver/samples/bulk_regular_insert.sql");

output(
   sub { pt_archiver::main("--source", "F=$cnf,D=bri,t=t,L=1", qw(--dest t=t_arch --where 1=1 --bulk-insert --limit 3)) },
);
$sb->wait_for_slaves(master => 'node4', slave => 'node5');

$sql = 'select * from bri.t order by id';
is_deeply(
   $node5_dbh->selectall_arrayref($sql),
   $node4_dbh->selectall_arrayref($sql),
   "--bulk-insert works as expected on the source table"
);

$sql = 'select * from bri.t_arch order by id';
is_deeply(
   $node5_dbh->selectall_arrayref($sql),
   $node4_dbh->selectall_arrayref($sql),
   "...and on the dest table"
);

# #############################################################################
# Test --bulk-delete
# #############################################################################

$sb->load_file('node4', 't/pt-archiver/samples/table5.sql');
$output = output(
   sub { pt_archiver::main(qw(--no-ascend --limit 50 --bulk-delete --where 1=1), "--source", "D=test,t=table_5,F=$cnf", qw(--statistics --dest t=table_5_dest)) },
);
$sb->wait_for_slaves(master => 'node4', slave => 'node5');

$sql = 'select * from test.table_5';
is_deeply(
   $node5_dbh->selectall_arrayref($sql),
   $node4_dbh->selectall_arrayref($sql),
   "--bulk-delete works as expected on the source table"
);

$sql = 'select * from test.table_5_dest';
is_deeply(
   $node5_dbh->selectall_arrayref($sql),
   $node4_dbh->selectall_arrayref($sql),
   "...and on the dest table"
);

# Same as above, but with a twist: --dest points to the second node. We should
# get the archieved rows in the first node as well

my $node5_dsn = $sb->dsn_for('node5');
my $node5_cnf = $sb->config_file_for('node5');

$sb->load_file('node4', 't/pt-archiver/samples/table5.sql');
$sb->wait_for_slaves(master => 'node4', slave => 'node5');
$output = output(
   sub { pt_archiver::main(qw(--no-ascend --limit 50 --bulk-delete --where 1=1),
                           "--source", "D=test,t=table_5,F=$cnf", qw(--statistics),
                           "--dest", "$node5_dsn,D=test,t=table_5_dest,F=$node5_cnf") },
);
# Wait for the --dest table to replicate back
$sb->wait_for_slaves(master => 'node5', slave => 'node4');

$sql = 'select * from test.table_5_dest';
is_deeply(
   $node5_dbh->selectall_arrayref($sql),
   $node4_dbh->selectall_arrayref($sql),
   "--bulk-delete with --dest on the second node, archive ends up in node1 as well"
);

$sb->load_file('node4', "t/pt-archiver/samples/bulk_regular_insert.sql");
$sb->wait_for_slaves(master => 'node4', slave => 'node5');
output(
   sub { pt_archiver::main("--source", "F=$cnf,D=bri,t=t,L=1",
                           "--dest", "$node5_dsn,D=bri,t=t_arch,F=$node5_cnf",
                           qw(--where 1=1 --bulk-insert --limit 3)) },
);
$sb->wait_for_slaves(master => 'node5', slave => 'node4');

$sql = 'select * from bri.t_arch';
is_deeply(
   $node5_dbh->selectall_arrayref($sql),
   $node4_dbh->selectall_arrayref($sql),
   "--bulk-insert with --dest on the second node, archive ends up in node1 as well"
);

# #############################################################################
# Done.
# #############################################################################
$sb->stop_sandbox(qw(node4 node5));
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;
