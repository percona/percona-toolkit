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

$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

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

my $output;
my $dsn  = $sb->dsn_for('master');
my @args = ($dsn, qw(--iterations 1));

$dbh1->commit;
$dbh2->commit;
$sb->wipe_clean($dbh1);
$sb->create_dbs($dbh1, ['test']);

# Set up the table for creating a deadlock.
$dbh1->do("create table test.dl(a int) engine=innodb");
$dbh1->do("insert into test.dl(a) values(0), (1)");
$dbh1->commit;
$dbh2->commit;
$dbh1->{InactiveDestroy} = 1;
$dbh2->{InactiveDestroy} = 1;

sub make_deadlock {
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
   $dbh1->commit;
   $dbh2->commit;
}

make_deadlock();

# Test that there is a deadlock
$output = $dbh1->selectrow_hashref('show /*!40101 engine*/ innodb status')->{status};
like($output, qr/WE ROLL BACK/, 'There was a deadlock');

$output = output(
   sub {
      pt_deadlock_logger::main(@args);
   }
);

like(
   $output,
   qr/127\.1.+msandbox.+GEN_CLUST_INDEX/,
   'Deadlock logger prints the output'
);

$output = output(
   sub {
      pt_deadlock_logger::main(@args, qw(--quiet));
   }
);

is(
   $output,
   "",
   "No output with --quiet"
);

# #############################################################################
# Issue 943: mk-deadlock-logger reports the same deadlock with --interval
# #############################################################################

# The deadlock from above won't be re-printed so even after running for
# 3 seconds and checking multiple times only the single, 3 line deadlock
# should be reported.

$output = output(
   sub {
      pt_deadlock_logger::main(@args, qw(--run-time 3));
   }
);
$output =~ s/^\s+//;
my @lines = split("\n", $output);
is(
   scalar @lines,
   3,
   "Doesn't re-print same deadlock (issue 943)"
) or diag($output);

# #############################################################################
# Check that deadlocks from previous test were stored in table.
# #############################################################################
$output = output(
   sub {
      pt_deadlock_logger::main(@args, '--dest', 'D=test,t=deadlocks',
         qw(--create-dest-table))
   }
);

my $res = $dbh1->selectall_arrayref('SELECT * FROM test.deadlocks');
ok(
   scalar @$res,
   'Deadlock saved in --dest table'
) or diag($output);

# #############################################################################
# In 2.1, --dest suppressed output (--print).  In 2.2, output is only
# suppressed by --quiet.
# #############################################################################
$output = '';
$dbh1->do('TRUNCATE TABLE test.deadlocks');
$output = output(
   sub {
      pt_deadlock_logger::main(@args, '--dest', 'D=test,t=deadlocks',
         qw(--quiet))
   }
);

is(
   $output,
   "",
   "No output with --dest and --quiet"
);

$res = $dbh1->selectall_arrayref('SELECT * FROM test.deadlocks');
ok(
   scalar @$res,
   "... deadlock still saved in the table"
);

# #############################################################################
# Bug 1043528: pt-deadlock-logger can't parse db/tbl/index on partitioned tables
# #############################################################################
SKIP: {
   skip "Deadlock with partitions test requires MySQL 5.1 and newer", 1
      unless $sandbox_version ge '5.1';

   $dbh1->do('rollback');
   $dbh2->do('rollback');
   $output = 'foo';
   $dbh1->do('TRUNCATE TABLE test.deadlocks');

   $sb->load_file('master', "t/pt-deadlock-logger/samples/dead-lock-with-partitions.sql");

   make_deadlock();

   $output = output(
      sub { pt_deadlock_logger::main(@args) }
   );

   like(
      $output,
      qr/test dl PRIMARY RECORD/,
      "Deadlock with partitions (bug 1043528)"
   );
}

# #############################################################################
# Done.
# #############################################################################
$dbh1->commit;
$dbh2->commit;
$sb->wipe_clean($dbh1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
