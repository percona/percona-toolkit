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
else {
   plan tests => 9;
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

   my %ids;
   foreach my $line ( @lines ) {
      my ($stmt, $ids) = split(':', $line);
      chomp $ids;
      $ids{$stmt} = $ids;
   }

   return \%ids;
}

sub check_ids {
   my ( $db, $tbl, $pkcol, $ids ) = @_;
   my $rows;

   my $n_updated  = $ids->{updated} ? ($ids->{updated}  =~ tr/,//) : 0;
   my $n_deleted  = $ids->{deleted} ? ($ids->{deleted}  =~ tr/,//) : 0;
   my $n_inserted = ($ids->{inserted} =~ tr/,//);

   # "1,1"=~tr/,// returns 1 but is 2 values
   $n_updated++ if $n_updated;
   $n_deleted++ if $n_deleted;
   $n_inserted++;

   $rows = $master_dbh->selectrow_arrayref(
      "SELECT COUNT($pkcol) FROM $db.$tbl");
   is(
      $rows->[0],
      500 + $n_inserted - $n_deleted,
      "New table row count: 500 original + $n_inserted inserted - $n_deleted deleted"
   ) or print Dumper($rows);

   $rows = $master_dbh->selectall_arrayref(
      "SELECT $pkcol FROM $db.$tbl WHERE $pkcol > 500 AND $pkcol NOT IN ($ids->{inserted})");
   is_deeply(
      $rows,
      [],
      "No extra rows inserted in new table"
   ) or print Dumper($rows);

   if ( $n_deleted ) {
      $rows = $master_dbh->selectall_arrayref(
         "SELECT $pkcol FROM $db.$tbl WHERE $pkcol IN ($ids->{deleted})");
      is_deeply(
         $rows,
         [],
         "No deleted rows present in new table"
      ) or print Dumper($rows);
   }
   else {
      ok(
         1,
         "No rows deleted"
      );
   };

   if ( $n_updated ) {
      my $sql = "SELECT $pkcol FROM $db.$tbl WHERE $pkcol IN ($ids->{updated}) "
              . "AND c NOT LIKE 'updated%'";
      $rows = $master_dbh->selectall_arrayref($sql);
      is_deeply(
         $rows,
         [],
         "Updated rows correct in new table"
      ) or print Dumper($rows);
   }
   else {
      ok(
         1,
         "No rows updated"
      );
   }

   return;
}
   
# #############################################################################
# Attempt to alter a table while another process is changing it.
# #############################################################################

# Load 500 rows.
diag('Loading sample dataset...');
$sb->load_file('master', "$sample/basic_no_fks.sql");
$master_dbh->do("USE pt_osc");
$master_dbh->do("TRUNCATE TABLE t");
$master_dbh->do("LOAD DATA LOCAL INFILE '$trunk/t/pt-online-schema-change/samples/basic_no_fks.data' INTO TABLE t");
$master_dbh->do("ANALYZE TABLE t");
$sb->wait_for_slaves();

$rows = $master_dbh->selectrow_hashref('show master status');
diag('Binlog position before altering table: ', $rows->{file}, '/', $rows->{position});

# Start inserting, updating, and deleting rows at random.
start_query_table(qw(pt_osc t id));

# While that's ^ happening, alter the table.
($output, $exit) = full_output(
   sub { pt_online_schema_change::main(
      "$master_dsn,D=pt_osc,t=t",
      qw(--lock-wait-timeout 5),
      qw(--print --execute --chunk-size 100 --alter ENGINE=InnoDB)) },
   stderr => 1,
);

# Stop changing the table's data.
stop_query_table();

like($output, qr/Successfully altered `pt_osc`.`t`/, 'Altered OK');

$rows = $master_dbh->selectall_hashref('SHOW TABLE STATUS FROM pt_osc', 'name');
is(
   $rows->{t}->{engine},
   'InnoDB',
   "New table ENGINE=InnoDB"
) or BAIL_OUT("Something went terribly wrong");

is(
   scalar keys %$rows,
   1,
   "Dropped old table"
);

is(
   $exit,
   0,
   "Exit status 0"
);

check_ids(qw(pt_osc t id), get_ids());

# #############################################################################
# Done.
# #############################################################################
unlink $query_table_stop or warn $OS_ERROR;
unlink $query_table_output or warn $OS_ERROR;
unlink $query_table_pid or warn $OS_ERROR;
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
