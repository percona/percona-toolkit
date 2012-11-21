#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use DBI;
use Time::HiRes qw(sleep time);
use Test::More qw();

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

my ($host, $port, $db, $tbl, $pkcol, $stop_file, $pid_file, $sleep) = @ARGV;

die "I need a pid_file argument" unless $pid_file;
open my $fh, '>', $pid_file or die $OS_ERROR;
print $fh $PID;
close $fh;

my $dbh = DBI->connect(
   "DBI:mysql:$db;host=$host;port=$port;mysql_read_default_group=client",
   'msandbox', 'msandbox',
   {RaiseError => 1, AutoCommit => 0, ShowErrorStatement => 1, PrintError => 0},
);

$sleep ||= 0.01;

my $cnt   = 0;
my (@del, %del);
my (@upd, %upd);
my (@ins, %ins);

use constant TYPE_DELETE => 1;
use constant TYPE_UPDATE => 2;

sub new_transaction {
   @del = ();
   @ins = ();
   @upd = ();
   $cnt = 0;

   $dbh->do("START TRANSACTION /*!40108 WITH CONSISTENT SNAPSHOT */");
}

sub commit {
   eval {
      $dbh->commit;
   };
   if ( $EVAL_ERROR ) {
      Test::More::diag($EVAL_ERROR);
   }
   else {
      map { $del{$_}++ } @del;
      map { $ins{$_}++ } @ins;
      map { $upd{$_}++ } @upd;
   }
   new_transaction();
}

new_transaction();  # first transaction

for my $i ( 1..5_000 ) {
   last if -f $stop_file;
   my $id   = 0;
   my $type = '';
   eval {
      # We do roughly 25% DELETE, 25% UPDATE and 50% INSERT.
      my $type = int(rand(5));
      if ($type == TYPE_DELETE) {
         $id = int(rand(500)) || 1;
         $dbh->do("delete from $db.$tbl where $pkcol=$id");
         # To challenge the tool, we *do* (or can) delete the same id twice.
         # But to keep the numbers straight, we only record each deleted
         # id once.
         push @del, $id;
      }
      elsif ($type == TYPE_UPDATE) {
         $id = int(rand(500)) || 1;
         # Update a row if we haven't already deleted it.
         if ( !$del{$id} ) {
            my $t=time;
            $dbh->do("update $db.$tbl set c='updated row $t' where $pkcol=$id");
            push @upd, $id;
         }
      }
      else {
         $id = 500 + $i;
         my $t  = time;
         $dbh->do("insert ignore into $db.$tbl ($pkcol, c) values ($id, 'new row $t')");
         push @ins, $id;
      }
   };
   if ( $EVAL_ERROR ) {
      Test::More::diag($EVAL_ERROR);
      new_transaction();
   }

   # COMMIT every N statements.  With PXC this can fail.
   if ( $cnt++ > 5 ) {
      commit();
      new_transaction();
   }

   sleep($sleep);
}

commit();
$dbh->disconnect();

print "deleted:"  . join(',', sort keys %del) . "\n";
print "updated:"  . join(',', sort keys %upd) . "\n";
print "inserted:" . join(',', sort keys %ins) . "\n";

exit 0;
