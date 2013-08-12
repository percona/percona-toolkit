#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::HiRes qw(sleep);
use Test::More;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-kill";

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');
my $target_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$target_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master (target)';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}

my $output;
my $master_dsn = $sb->dsn_for('master');
my $master_cnf = $sb->cnf_for('master');
my $slave_dsn  = $sb->dsn_for('slave1');

# Create the --log-dsn table.
$sb->create_dbs($master_dbh, [qw(kill_test)]);
my $log_table = "kill_test.log_table";
my $log_dsn   = "D=kill_test,t=log_table";
my $log_sql   = OptionParser->read_para_after(
   "$trunk/bin/pt-kill", qr/MAGIC_create_log_table/);
$log_sql =~ s/kill_log/$log_table/;
$master_dbh->do($log_sql);
$sb->wait_for_slaves();

# Create the target db for --match-db.
my $target_db = "x$PID";
$sb->create_dbs($target_dbh, [$target_db]);

sub setup_target {
   eval {
      $target_dbh->do("SELECT 1");
   };
   if ( $EVAL_ERROR ) {
      eval {
         $target_dbh->disconnect();
      };
      $target_dbh = $sb->get_dbh_for('master');
   }
   $target_dbh->do("USE $target_db");
}

# #############################################################################
# Require D and t in --log-dsn
# #############################################################################

foreach my $test (
   [q/h=127.1,P=12345,u=msandbox,p=msandbox/, 'D and t'],
   [q/h=127.1,P=12345,u=msandbox,p=msandbox,t=log_table/, 'D'],
   [q/h=127.1,P=12345,u=msandbox,p=msandbox,D=kill_test/, 't'],
) {
   eval {
      pt_kill::main($master_dsn, qw(--kill --run-time 1 --interval 1),
         "--match-db", $target_db,
         "--log-dsn", $test->[0],
      )
   };
   like(
      $EVAL_ERROR,
      qr/\Q--log-dsn does not specify a database (D) or a database-qualified table (t)\E/,
      "--log-dsn croaks if missing $test->[1]"
   );
}

# #############################################################################
# Basic usage
# #############################################################################

eval {
   setup_target();
   pt_kill::main($master_dsn, qw(--kill --run-time 1 --interval 1),
      "--match-db", $target_db,
      "--log-dsn", "$master_dsn,$log_dsn"
   )
};

is(
   $EVAL_ERROR,
   '',
   "--log-dsn with existing log table, no error"
);

# Should get a row like:
# $VAR1 = [
#   {
#      command => 'Sleep',
#      db => 'x32282',
#      host => 'localhost:62581',
#      id => '365',
#      info => undef,
#      kill_error => '',
#      kill_id => '1',
#      reason => 'Query matches db spec',
#      server_id => '12345',
#      state => '',
#      time => '0',
#      time_ms => undef,
#      timestamp => '2013-08-12 12:46:26',
#      user => 'msandbox'
#   }
# ];
my $rows = $master_dbh->selectall_arrayref(
   "SELECT * FROM $log_table", { Slice =>{} });

is(
   scalar @$rows,
   1,
   "... which contains one row"
) or diag(Dumper($rows));

is(
   $rows->[0]->{db},
   $target_db,
   "... got the target db"
) or diag(Dumper($rows));

is(
   $rows->[0]->{server_id},
   12345,
   "... on the correct server"
) or diag(Dumper($rows));

is(
   $rows->[0]->{reason},
   'Query matches db spec',
   "... correct kill reason"
) or diag(Dumper($rows));

# Get the current ts in MySQL's format.
my $current_ts = Transformers::ts(time());
($current_ts) = $master_dbh->selectrow_array("SELECT TIMESTAMP('$current_ts')");

# Chop off the minutes & seconds. If the rest of the date is right,
# this is unlikely to be broken.
substr($current_ts, -5, 5, "");
like(
   $rows->[0]->{timestamp},
   qr/\A\Q$current_ts\E.{5}\Z/,
   "... timestamp is correct (bug 1086259)"
);

my $against = {
   user    => 'msandbox',
   host    => 'localhost',
   db      => $target_db,
   command => 'Sleep',
   state   => '', #($sandbox_version lt '5.1' ? "executing" : "User sleep"),
   info    => undef,
};
my %trimmed_result;
@trimmed_result{ keys %$against } = @{$rows->[0]}{ keys %$against };
$trimmed_result{host} =~ s/localhost:[0-9]+/localhost/;

is_deeply(
   \%trimmed_result,
   $against,
   "... populated as expected",
) or diag(Dumper($rows));

# #############################################################################
# --create-log-table
# #############################################################################

# XXX This test assumes that the log table exists from previous tests.

eval {
   setup_target();
   pt_kill::main('-F', $master_cnf, qw(--kill --run-time 1 --interval 1),
      "--create-log-table",
      "--match-info", 'select sleep\(4\)',
      "--log-dsn", "$master_dsn,$log_dsn",
   )
};

is(
   $EVAL_ERROR,
   '',
   "--log-dsn --create-log-table and the table exists, no error"
);

$master_dbh->do("DROP TABLE IF EXISTS $log_table");
$sb->wait_for_slaves();

eval {
   setup_target();
   pt_kill::main('-F', $master_cnf, qw(--kill --run-time 1 --interval 1),
      "--create-log-table",
      "--match-info", 'select sleep\(4\)',
      "--log-dsn", "$master_dsn,$log_dsn",
   )
};

is(
   $EVAL_ERROR,
   '',
   "--log-dsn --create-log-table and the table doesn't exist, no error"
);

$master_dbh->do("DROP TABLE IF EXISTS $log_table");
$sb->wait_for_slaves();

eval {
   setup_target();
   pt_kill::main('-F', $master_cnf, qw(--kill --run-time 1 --interval 1),
      "--match-info", 'select sleep\(4\)',
      "--log-dsn", "$master_dsn,$log_dsn",
   )
};

like(
   $EVAL_ERROR,
   qr/\Q--log-dsn table does not exist. Please create it or specify\E/,
   "--create-log-table is off by default"
);

# Re-create the log table for the next tests.
$master_dbh->do($log_sql);
$sb->wait_for_slaves();

# #############################################################################
# Can re-use the log table.
# #############################################################################

for (1,2) {
   setup_target();
   pt_kill::main($master_dsn, qw(--kill --run-time 1 --interval 1),
      "--create-log-table",
      "--match-db", $target_db,
      "--log-dsn", "$master_dsn,$log_dsn",
   );
   sleep 0.5;
}

$rows = $master_dbh->selectall_arrayref("SELECT * FROM $log_table");

is(
   scalar @$rows,
   2,
   "Different --log-dsn runs reuse the log table"
) or diag(Dumper($rows));

# #############################################################################
# --log-dsn and --daemonize
# https://bugs.launchpad.net/percona-toolkit/+bug/1209436
# #############################################################################

$master_dbh->do("TRUNCATE $log_table");
$sb->wait_for_slaves();

my $pid_file = "/tmp/pt-kill-test.$PID";
my $log_file = "/tmp/pt-kill-test-log.$PID";
diag(`rm -f $pid_file $log_file >/dev/null 2>&1`);

setup_target();
system("$trunk/bin/pt-kill $master_dsn --daemonize --run-time 1 --kill-query --interval 1 --match-db $target_db --log-dsn $slave_dsn,$log_dsn --pid $pid_file --log $log_file");
PerconaTest::wait_for_files($pid_file);         # start
# ...                                           # run
PerconaTest::wait_until(sub { !-f $pid_file});  # stop

# Should *not* log to master
$rows = $master_dbh->selectall_arrayref("SELECT * FROM $log_table");
ok(
   !@$rows,
   "--log-dsn --daemonize, master (bug 1209436)",
) or diag(Dumper($rows));

# Should log to slave
$rows = $slave_dbh->selectall_arrayref("SELECT * FROM $log_table");
ok(
   scalar @$rows,
   "--log-dsn --daemonize, slave (bug 1209436)"
) or diag(Dumper($rows));

# #############################################################################
# --log-dsn in a --config file
# https://bugs.launchpad.net/percona-toolkit/+bug/1209436
# #############################################################################

$master_dbh->do("TRUNCATE $log_table");
$sb->wait_for_slaves();

my $cnf_file = "/tmp/pt-kill-test.cnf.$PID";
diag(`rm -f $pid_file $log_file $cnf_file >/dev/null 2>&1`);

open my $fh, '>', $cnf_file or die "Error opening $cnf_file: $OS_ERROR";
print { $fh } <<EOF;
defaults-file=$master_cnf
log-dsn=$slave_dsn,$log_dsn
daemonize
run-time=1
kill-query
interval=1
match-db=$target_db
pid=$pid_file
log=$log_file
EOF
close $fh;

setup_target();
system("$trunk/bin/pt-kill --config $cnf_file");
PerconaTest::wait_for_files($pid_file);         # start
# ...                                           # run
PerconaTest::wait_until(sub { !-f $pid_file});  # stop

# Should *not* log to master
$rows = $master_dbh->selectall_arrayref("SELECT * FROM $log_table");
ok(
   !@$rows,
   "--log-dsn in --config file, master (bug 1209436)",
) or diag(Dumper($rows));

# Should log to slave
$rows = $slave_dbh->selectall_arrayref("SELECT * FROM $log_table");
ok(
   scalar @$rows,
   "--log-dsn in --config file, slave (bug 1209436)"
) or diag(Dumper($rows));

diag(`rm -f $pid_file $log_file $cnf_file >/dev/null 2>&1`);

# #############################################################################
# Done.
# #############################################################################
eval { $target_dbh->disconnect() };
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
