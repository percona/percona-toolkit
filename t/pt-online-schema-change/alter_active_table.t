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
require "$trunk/bin/pt-online-schema-change";
require VersionParser;

use Time::HiRes qw(sleep);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}

my $output;
my $master_dsn = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $sample     = "t/pt-online-schema-change/samples";
my $exit;
my $rows;

my $query_table_stop   = "/tmp/query_table.$PID.stop";
my $query_table_pid    = "/tmp/query_table.$PID.pid";
my $query_table_output = "/tmp/query_table.$PID.output";

sub start_query_table {
   my ($db, $tbl, $pkcol) = @_;

   diag(`rm -rf $query_table_stop`);
   diag(`echo > $query_table_output`);

   my $cmd = "$trunk/$sample/query_table.pl";
   system("$cmd 127.1 12345 $db $tbl $pkcol $query_table_stop $query_table_pid >$query_table_output &");
   wait_until(sub{-e $query_table_pid});

   return;
}

sub stop_query_table {
   diag(`touch $query_table_stop`);
   open my $fh, '<', $query_table_pid or die $OS_ERROR;
   my ($p) = <$fh>;
   close $fh;
   chomp $p;
   wait_until(sub{!kill 0, $p});
   return;
}

sub get_ids {
   open my $fh, '<', $query_table_output
      or die "Cannot open $query_table_output: $OS_ERROR";
   my @lines = <$fh>;
   close $fh;

   my %ids = (
      updated  => '',
      deleted  => '',
      inserted => '',
   );
   foreach my $line ( @lines ) {
      my ($stmt, $ids) = split(':', $line);
      chomp $ids;
      $ids{$stmt} = $ids || '';
   }

   return \%ids;
}

sub check_ids {
   my ( $db, $tbl, $pkcol, $ids, $test ) = @_;
   my $rows;

   my $n_updated  = $ids->{updated} ? ($ids->{updated}  =~ tr/,//) : 0;
   my $n_deleted  = $ids->{deleted} ? ($ids->{deleted}  =~ tr/,//) : 0;
   my $n_inserted = $ids->{inserted} ?($ids->{inserted} =~ tr/,//) : 0;

   # "1,1"=~tr/,// returns 1 but is 2 values
   $n_updated++ if $n_updated;
   $n_deleted++ if $n_deleted;
   $n_inserted++;

   $rows = $master_dbh->selectrow_arrayref(
      "SELECT COUNT($pkcol) FROM $db.$tbl");
   is(
      $rows->[0],
      500 + $n_inserted - $n_deleted,
      "$test: new table rows: 500 original + $n_inserted inserted - $n_deleted deleted"
   ) or diag(Dumper($rows));

   $rows = $master_dbh->selectall_arrayref(
      "SELECT $pkcol FROM $db.$tbl WHERE $pkcol > 500 AND $pkcol NOT IN ($ids->{inserted})");
   is_deeply(
      $rows,
      [],
      "$test: no extra rows inserted in new table"
   ) or diag(Dumper($rows));

   if ( $n_deleted ) {
      $rows = $master_dbh->selectall_arrayref(
         "SELECT $pkcol FROM $db.$tbl WHERE $pkcol IN ($ids->{deleted})");
      is_deeply(
         $rows,
         [],
         "$test: no deleted rows present in new table"
      ) or diag(Dumper($rows));
   }
   else {
      ok(
         1,
         "$test: no rows deleted"
      );
   };

   if ( $n_updated ) {
      my $sql = "SELECT $pkcol FROM $db.$tbl WHERE $pkcol IN ($ids->{updated}) "
              . "AND c NOT LIKE 'updated%'";
      $rows = $master_dbh->selectall_arrayref($sql);
      is_deeply(
         $rows,
         [],
         "$test: updated rows correct in new table"
      ) or diag(Dumper($rows));
   }
   else {
      ok(
         1,
         "$test: no rows updated"
      );
   }

   return;
}
   
# #############################################################################
# Attempt to alter a table while another process is changing it.
# #############################################################################

my $db_flavor = VersionParser->new($master_dbh)->flavor();
if ( $db_flavor =~ m/XtraDB Cluster/ ) {
   $sb->load_file('master', "$sample/basic_no_fks_innodb.sql");
}
else {
   $sb->load_file('master', "$sample/basic_no_fks.sql");
}
$master_dbh->do("USE pt_osc");
$master_dbh->do("TRUNCATE TABLE t");
$master_dbh->do("LOAD DATA INFILE '$trunk/t/pt-online-schema-change/samples/basic_no_fks.data' INTO TABLE t");
$master_dbh->do("ANALYZE TABLE t");
$sb->wait_for_slaves();

# Start inserting, updating, and deleting rows at random.
start_query_table(qw(pt_osc t id));

# While that's ^ happening, alter the table.
($output, $exit) = full_output(
   sub { pt_online_schema_change::main(
      "$master_dsn,D=pt_osc,t=t",
      qw(--set-vars innodb_lock_wait_timeout=5),
      qw(--print --execute --chunk-size 100 --alter ENGINE=InnoDB)) },
   stderr => 1,
);

# Stop changing the table's data.
stop_query_table();

like(
   $output,
   qr/Successfully altered `pt_osc`.`t`/,
   'Change engine: altered OK'
);

$rows = $master_dbh->selectall_hashref('SHOW TABLE STATUS FROM pt_osc', 'name');
is(
   $rows->{t}->{engine},
   'InnoDB',
   "Change engine: new table ENGINE=InnoDB"
) or warn Dumper($rows);

is(
   scalar keys %$rows,
   1,
   "Change engine: dropped old table"
);

is(
   $exit,
   0,
   "Change engine: exit status 0"
);

# #############################################################################
# Check that triggers work when renaming a column
# #############################################################################

$master_dbh->do("USE pt_osc");
$master_dbh->do("TRUNCATE TABLE t");
$master_dbh->do("LOAD DATA INFILE '$trunk/t/pt-online-schema-change/samples/basic_no_fks.data' INTO TABLE t");
$master_dbh->do("ANALYZE TABLE t");
$sb->wait_for_slaves();

# Start inserting, updating, and deleting rows at random.
start_query_table(qw(pt_osc t id));

# While that's ^ happening, alter the table.
($output, $exit) = full_output(
   sub { pt_online_schema_change::main(
      "$master_dsn,D=pt_osc,t=t",
      qw(--set-vars innodb_lock_wait_timeout=5),
      qw(--print --execute --chunk-size 100 --no-check-alter),
      '--alter', 'CHANGE COLUMN d q date',
   ) },
   stderr => 1,
);

# Stop changing the table's data.
stop_query_table();

like(
   $output,
   qr/Successfully altered `pt_osc`.`t`/,
   'Rename column: altered OK'
);

is(
   $exit,
   0,
   "Rename columnn: exit status 0"
);

check_ids(qw(pt_osc t id), get_ids(), "Rename column");

# #############################################################################
# Done.
# #############################################################################
unlink $query_table_stop or warn $OS_ERROR;
unlink $query_table_output or warn $OS_ERROR;
unlink $query_table_pid or warn $OS_ERROR;
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
