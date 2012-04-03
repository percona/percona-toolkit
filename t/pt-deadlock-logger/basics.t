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
require "$trunk/bin/pt-deadlock-logger";

my $dp   = new DSNParser(opts=>$dsn_opts);
my $sb   = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master', { PrintError => 0, RaiseError => 1, AutoCommit => 0 });
my $dbh2 = $sb->get_dbh_for('master', { PrintError => 0, RaiseError => 1, AutoCommit => 0 });

if ( !$dbh1 || !$dbh2 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 9;
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-deadlock-logger -F $cnf h=127.1";

$sb->wipe_clean($dbh1);
$sb->create_dbs($dbh1, ['test']);

# Set up the table for creating a deadlock.
$dbh1->do("create table test.dl(a int) engine=innodb");
$dbh1->do("insert into test.dl(a) values(0), (1)");
$dbh1->commit;
$dbh1->{InactiveDestroy} = 1;
$dbh2->{InactiveDestroy} = 1;

# Fork off two children to deadlock against each other.
my %children;
foreach my $child ( 0..1 ) {
   my $pid = fork();
   if ( defined($pid) && $pid == 0 ) { # I am a child
      eval {
         my $dbh = ($dbh1, $dbh2)[$child];
         my @stmts = (
            "set transaction isolation level serializable",
            "begin",
            "select * from test.dl where a = $child",
            "update test.dl set a = $child where a <> $child",
         );
         foreach my $stmt (@stmts[0..2]) {
            $dbh->do($stmt);
         }
         sleep(1 + $child);
         $dbh->do($stmts[-1]);
      };
      if ( $EVAL_ERROR ) {
         if ( $EVAL_ERROR !~ m/Deadlock found/ ) {
            die $EVAL_ERROR;
         }
      }
      exit(0);
   }
   elsif ( !defined($pid) ) {
      die("Unable to fork for clearing deadlocks!\n");
   }

   # I already exited if I'm a child, so I'm the parent.
   $children{$child} = $pid;
}

# Wait for the children to exit.
foreach my $child ( keys %children ) {
   my $pid = waitpid($children{$child}, 0);
}

# Test that there is a deadlock
$output = $dbh1->selectrow_hashref('show /*!40101 engine*/ innodb status')->{status};
like($output, qr/WE ROLL BACK/, 'There was a deadlock');

$output = `$cmd --print`;
like(
   $output,
   qr/127\.1.+msandbox.+GEN_CLUST_INDEX/,
   'Deadlock logger prints the output'
);

$output = `$cmd`;
like(
   $output,
   qr/127\.1.+msandbox.+GEN_CLUST_INDEX/,
   '--print is implicit'
);


# #############################################################################
# Issue 943: mk-deadlock-logger reports the same deadlock with --interval
# #############################################################################

# The deadlock from above won't be re-printed so even after running for
# 3 seconds and checking multiple times only the single, 3 line deadlock
# should be reported.
chomp($output = `$cmd --run-time 3 | wc -l`);
$output =~ s/^\s+//;
is(
   $output,
   3,
   "Doesn't re-print same deadlock (issue 943)"
);

# #############################################################################
# Check that deadlocks from previous test were stored in table.
# #############################################################################
`$cmd --dest D=test,t=deadlocks --create-dest-table`;
my $res = $dbh1->selectall_arrayref('SELECT * FROM test.deadlocks');
ok(
   scalar @$res,
   'Deadlocks recorded in --dest table'
);

# #############################################################################
# Check that --dest suppress --print output unless --print is explicit.
# #############################################################################
$output = 'foo';
$dbh1->do('TRUNCATE TABLE test.deadlocks');
$output = `$cmd --dest D=test,t=deadlocks`;
is(
   $output,
   '',
   'No output with --dest'
);

$res = $dbh1->selectall_arrayref('SELECT * FROM test.deadlocks');
ok(
   scalar @$res,
   'Deadlocks still recorded in table'
);

$output = '';
$dbh1->do('TRUNCATE TABLE test.deadlocks');
$output = `$trunk/bin/pt-deadlock-logger --print --dest D=test,t=deadlocks --host 127.1 --port 12345 --user msandbox --password msandbox`;
like(
   $output,
   qr/127\.1.+msandbox.+GEN_CLUST_INDEX/,
   'Prints output with --dest and explicit --print'
);

$res = $dbh1->selectall_arrayref('SELECT * FROM test.deadlocks');
ok(
   scalar @$res,
   'Deadlocks recorded in table again'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh1);
exit;
