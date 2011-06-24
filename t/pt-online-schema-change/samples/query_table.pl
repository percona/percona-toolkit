#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use DBI;
use Time::HiRes qw(usleep);

my ($host, $port, $db, $tbl, $pkcol, $sleep_time) = @ARGV;
my $dbh = DBI->connect(
   "DBI:mysql:$db;host=$host;port=$port;mysql_read_default_group=client",
   'msandbox', 'msandbox',
   {RaiseError => 1, AutoCommit => 0, ShowErrorStatement => 1, PrintError => 0},
);

my $sleep = ($sleep_time || 0.001) * 1_000_000;
my $cnt   = 0;
my @del;
my @upd;
my @ins;

my $start_xa = "START TRANSACTION /*!40108 WITH CONSISTENT SNAPSHOT */";
$dbh->do($start_xa);

for my $i ( 1..5_000 ) {
   last if -f '/tmp/query_table.stop';

   eval {
      # We do roughly 25% DELETE, 25% UPDATE and 50% INSERT.
      my $x = int(rand(5));
      if ($x == 1) {
         my $id = int(rand(500)) || 1;
         $dbh->do("delete from $db.$tbl where $pkcol=$id");
         # To challenge the tool, we *do* (or can) delete the same id twice.
         # But to keep the numbers straight, we only record each deleted
         # id once.
         push @del, $id unless grep { $_ == $id } @del;
      }
      elsif ($x == 2) {
         my $id = int(rand(500)) || 1;
         if ( !grep { $_ == $id } @del ) {
            $dbh->do("update $db.$tbl set c='updated' where $pkcol=$id");
            push @upd, $id;
         }
      }
      else {
         my $id = 500 + $i;
         $dbh->do("insert ignore into $db.$tbl ($pkcol, c) values ($id, 'inserted')");
         push @ins, $id;
      }

      # COMMIT every N statements
      if ( $cnt++ > 5 ) {
         $dbh->do('COMMIT');
         $cnt = 0;
         usleep($sleep);
         $dbh->do($start_xa);
      }
   };
   if ( $EVAL_ERROR ) {
      warn $EVAL_ERROR;
      last;
   }
}

$dbh->do('COMMIT');
$dbh->disconnect();

print "deleted:"  . join(',', @del) . "\n";
print "updated:"  . join(',', @upd) . "\n";
print "inserted:" . join(',', @ins) . "\n";

exit 0;
