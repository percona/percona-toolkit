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

my $del_sql = "DELETE FROM $db.$tbl WHERE $pkcol=?";
my $ins_sql = "INSERT INTO $db.$tbl ($pkcol, c) VALUES (?, ?)";
my $upd_sql = "UPDATE $db.$tbl SET c=? WHERE $pkcol=?";

my $del_sth = $dbh->prepare($del_sql);
my $ins_sth = $dbh->prepare($ins_sql);
my $upd_sth = $dbh->prepare($upd_sql);

$sleep ||= 0.01;

use constant TYPE_DELETE => 1;
use constant TYPE_UPDATE => 2;

my (@del, %del);
my (@upd, %upd);
my (@ins, %ins);
my $cnt  = 0;
my $id   = 0;
my $type = 0;

sub reset_counters {
   @del = ();
   @ins = ();
   @upd = ();
   $cnt = 0;
}

sub commit {
   eval {
      $dbh->commit;
   };
   if ( $EVAL_ERROR ) {
      #Test::More::diag($EVAL_ERROR);
      #Test::More::diag("lost deleted: @del");
      #Test::More::diag("lost updated: @upd");
      #Test::More::diag("lost inserted: @ins");
   }
   else {
      map { $del{$_}++ } @del;
      map { $ins{$_}++ } @ins;
      map { $upd{$_}++ } @upd;
   }
}

$dbh->do("START TRANSACTION");

for my $i ( 1..5_000 ) {
   last if -f $stop_file;
   eval {
      my $type = int(rand(5));  # roughly 25% DELETE, 25% UPDATE, 50% INSERT

      if ( $type == TYPE_DELETE ) {
         $id = int(rand(500)) || 1;
         $del_sth->execute($id);
         push @del, $id if $del_sth->rows;
      }
      elsif ( $type == TYPE_UPDATE ) {
         $id = int(rand(500)) || 1;
         if ( !$del{$id} && ($id <= 500 || $ins{$id}) ) {
            my $t = time;
            $upd_sth->execute("updated row $t", $id);
            push @upd, $id;
         }
      }
      else { # INSERT
         $id = 500 + $i;
         my $t  = time;
         $ins_sth->execute($id, "new row $t");
         push @ins, $id;
      }
   };
   if ( $EVAL_ERROR ) {
      #Test::More::diag($EVAL_ERROR);
      #Test::More::diag("lost deleted: @del");
      #Test::More::diag("lost updated: @upd");
      #Test::More::diag("lost inserted: @ins");
      reset_counters();
      sleep $sleep;
      $dbh->do("START TRANSACTION");
   }

   # COMMIT every N statements.  With PXC this can fail.
   if ( ++$cnt >= 5 ) {
      commit();
      reset_counters();
      sleep $sleep;
      # TODO: somehow this can fail if called very near when
      #       the old table is dropped.
      eval { $dbh->do("START TRANSACTION"); };
      if ( $EVAL_ERROR ) {
         #Test::More::diag($EVAL_ERROR);
      }
   }
   else {
      sleep 0.001;
   }
}

commit();
$dbh->disconnect();

print "deleted:"  . join(',', sort keys %del) . "\n";
print "updated:"  . join(',', sort keys %upd) . "\n";
print "inserted:" . join(',', sort keys %ins) . "\n";

exit 0;
