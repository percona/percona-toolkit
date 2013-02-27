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
require "$trunk/bin/pt-fk-error-logger";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

$sb->create_dbs($dbh, [qw(test)]);

my $output;
my $cnf  = '/tmp/12345/my.sandbox.cnf';
my $cmd  = "$trunk/bin/pt-fk-error-logger -F $cnf ";
my @args = qw(--iterations 1);

$sb->load_file('master', 't/pt-fk-error-logger/samples/fke_tbl.sql', 'test');

# #########################################################################
# Test saving foreign key errors to --dest.
# #########################################################################

# First, create a foreign key error.
`/tmp/12345/use -D test < $trunk/t/pt-fk-error-logger/samples/fke.sql 1>/dev/null 2>/dev/null`;

$output = output(
   sub {
      pt_fk_error_logger::main(@args, 'h=127.1,P=12345,u=msandbox,p=msandbox'),
   }
);

like(
   $output,
   qr/Foreign key constraint fails/,
   "Prints fk error by default"
);

$output = output(
   sub {
      pt_fk_error_logger::main(@args, 'h=127.1,P=12345,u=msandbox,p=msandbox',
         qw(--quiet))
   }
);

is(
   $output,
   "",
   "No output with --quiet"
);


# #############################################################################
# --dest
# #############################################################################

$output = output(
   sub {
      pt_fk_error_logger::main(@args,
         'h=127.1,P=12345,u=msandbox,p=msandbox',
         '--dest', 'h=127.1,P=12345,D=test,t=foreign_key_errors',
      )
   }
);

sleep 0.1;

# And then test that it was actually saved.
my $today = $dbh->selectall_arrayref('SELECT NOW()')->[0]->[0];
($today) = $today =~ m/(\d{4}-\d\d-\d\d)/;  # Just today's date.

my $fke = $dbh->selectall_arrayref('SELECT * FROM test.foreign_key_errors');
like(
   $fke->[0]->[0],  # Timestamp
   qr/$today/,
   'Saved foreign key error timestamp'
);
like(
   $fke->[0]->[1],  # Error
   qr/INSERT INTO child VALUES \(1, 9\)/,
   'Saved foreign key error'
);

# Check again to make sure that the same fke isn't saved twice.
my $first_ts = $fke->[0]->[0];
output(sub { pt_fk_error_logger::main(@args, 'h=127.1,P=12345,u=msandbox,p=msandbox', '--dest', 'h=127.1,P=12345,D=test,t=foreign_key_errors'); } );
sleep 0.1;
$fke = $dbh->selectall_arrayref('SELECT * FROM test.foreign_key_errors');
is(
   $fke->[0]->[0],  # Timestamp
   $first_ts,
   "Doesn't save same error twice",
);
is(
   scalar @$fke,
   1,
   "Still only 1 saved error"
);

# Make another fk error which should be saved.
sleep 1;
$dbh->do('USE test');
$dbh->do('INSERT INTO child VALUES (1, 2)');
eval {
   $dbh->do('DELETE FROM parent WHERE id = 2');  # Causes foreign key error.
};
output( sub { pt_fk_error_logger::main(@args, 'h=127.1,P=12345,u=msandbox,p=msandbox', '--dest', 'h=127.1,P=12345,D=test,t=foreign_key_errors'); } );
sleep 0.1;
$fke = $dbh->selectall_arrayref('SELECT * FROM test.foreign_key_errors');
like(
   $fke->[1]->[1],  # Error
   qr/DELETE FROM parent WHERE id = 2/,
   'Second foreign key error'
);
is(
   scalar @$fke,
   2,
   "Now 2 saved errors"
);

# ##########################################################################
# Test printing the errors.
# ##########################################################################

$dbh->do('USE test');
eval {
   $dbh->do('DELETE FROM parent WHERE id = 2');  # Causes foreign key error.
};

$output = output(sub { pt_fk_error_logger::main(@args, 'h=127.1,P=12345,u=msandbox,p=msandbox'); });

like(
   $output,
   qr/DELETE FROM parent WHERE id = 2/,
   'Print foreign key error'
);

# Drop these manually because $sb->wipe_clean() may not do them in the
# correct order causing a foreign key error that the next run of this
# test will see.
$dbh->do('DROP TABLE test.child');
$dbh->do('DROP TABLE test.parent');

# #############################################################################
# pt-fk-error-logger crashes if there's no foreign key error
# https://bugs.launchpad.net/percona-toolkit/+bug/1075773
# #############################################################################
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
diag(`$trunk/sandbox/start-sandbox master 12348 >/dev/null`);
diag(`/tmp/12348/use -e "create database test"`);
$sb->load_file('master1', 't/pt-fk-error-logger/samples/fke_tbl.sql', 'test');

$output = output(
   sub {
      pt_fk_error_logger::main(@args, 'h=127.1,P=12348,u=msandbox,p=msandbox',
      '--dest', 'h=127.1,P=12348,D=test,t=foreign_key_errors')
   },
   stderr => 1,
);

is(
   $output,
   "",
   "No foreign key errors, no errors, no output (bug 1075773)"
);

diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);

# #############################################################################
# Test --pid
# #############################################################################

my $pid_file = "/tmp/pt-fk-error-log-test-$PID.pid";
diag(`touch $pid_file`);

$output = `$trunk/bin/pt-fk-error-logger h=127.1,P=12345,u=msandbox,p=msandbox --pid $pid_file --iterations 1 2>&1`;

like(
   $output,
   qr{PID file $pid_file already exists},
   'Dies if PID file already exists (--pid without --daemonize) (issue 391)'
);

unlink $pid_file;

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
