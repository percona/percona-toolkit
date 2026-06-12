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
use Data::Dumper;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-heartbeat";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}
else {
   plan tests => 35;
}

diag(`rm -rf /tmp/pt-heartbeat-sentinel >/dev/null 2>&1`);
$sb->create_dbs($source_dbh, ['test']);
$sb->wait_for_replicas();

my $output;
my $pid_file = "/tmp/pt-heartbeat-test.$PID.pid";

# Multi-update mode is the new, hi-res mode that allows a single table to
# be updated by multiple servers: a replica's source, its source's source, etc.
#
# We have source -> replica1 -> replica2 where source has server_id=12345,
# replica1 server_id=12346, and replica2 server_id=12347.  The  heartbeat table
# on replica2 can have 3 heartbeat rows: one from the source, one from replica1
# and one for itself.
my @ports = qw(12345 12346 12347);

foreach my $port (@ports) {
   system("$trunk/bin/pt-heartbeat -h 127.1 -u msandbox -p msandbox -P $port --database test --table heartbeat --create-table --update --interval 0.5 --daemonize --pid $pid_file.$port >/dev/null");

   PerconaTest::wait_for_files("$pid_file.$port");
   ok(
      -f "$pid_file.$port",
      "--update on $port started"
   );
}
sleep 5;
# Check heartbeat on source.
my $rows = $source_dbh->selectall_hashref("select * from test.heartbeat", 'server_id');

is(
   scalar keys %$rows,
   1,
   "One heartbeat row on source"
);

ok(
   exists $rows->{12345},
   "Source heartbeat"
);

ok(
   defined $rows->{12345}->{file} && defined $rows->{12345}->{position},
   "Source file and position"
);

ok(
   !$rows->{12345}->{"relay_${source_name}_log_file"} && !$rows->{12345}->{"exec_${source_name}_log_pos"},
   "No relay_source_log_file or exec_source_log_pos for source"
);

# Check heartbeat on replica1.
$rows = $replica1_dbh->selectall_hashref("select * from test.heartbeat", 'server_id');

is(
   scalar keys %$rows,
   2,
   "Two heartbeat rows on replica1"
);

ok(
   exists $rows->{12345},
   "Replica1 has source heartbeat",
);

ok(
   exists $rows->{12346},
   "Replica1 heartbeat"
);

ok(
   defined $rows->{12346}->{file} && defined $rows->{12346}->{position},
   "Replica1 source file and position"
);

ok(
   $rows->{12346}->{"relay_source_log_file"} && $rows->{12346}->{"exec_source_log_pos"},
   "Replica1 relay_source_log_file and exec_source_log_pos for source"
) or diag(Dumper($rows));

# Check heartbeat on replica2.
$rows = $replica2_dbh->selectall_hashref("select * from test.heartbeat", 'server_id');

is(
   scalar keys %$rows,
   3,
   "Three heartbeat rows on replica2"
);

ok(
   exists $rows->{12345},
   "Replica2 has source heartbeat",
);

ok(
   exists $rows->{12346},
   "Replica2 has replica1 heartbeat",
);

ok(
   exists $rows->{12347},
   "Replica1 heartbeat"
);

ok(
   defined $rows->{12347}->{file} && defined $rows->{12347}->{position},
   "Replica2 source file and position"
);

ok(
   $rows->{12347}->{"relay_source_log_file"} && $rows->{12347}->{"exec_source_log_pos"},
   "Replica2 relay_source_log_file and exec_source_log_pos for source"
);

# ############################################################################
# Verify that the source heartbeat is changing and replicating.
# ############################################################################

# $rows already has replica2 heartbeat info.
sleep 4;

my $rows2 = $replica2_dbh->selectall_hashref("select * from test.heartbeat", 'server_id');

cmp_ok(
   $rows2->{12345}->{ts},
   'gt',
   $rows->{12345}->{ts},
   "Source heartbeat ts is changing and replicating"
);

cmp_ok(
   $rows2->{12345}->{position},
   '>',
   $rows->{12345}->{position},
   "Source binlog position is changing and replicating"
);

# But the source binlog file shouldn't change.
is(
   $rows->{12345}->{file},
   $rows2->{12345}->{file},
   "Source binlog file is not changing"
);


# ############################################################################
# Test --source-server-id.
# ############################################################################

# First, the option should be optional.  If not given, the server's
# immediate source should be used.
$output = output(
   sub { pt_heartbeat::main(qw(-h 127.1 -P 12347 -u msandbox -p msandbox),
      qw(-D test --check --print-source-server-id)) },
);

like(
   $output,
   qr/0\.\d\d\s+12346\n/,
   "--check 12347, automatic source server_id"
) or diag($output);

$output = output(
   sub { pt_heartbeat::main(qw(-h 127.1 -P 12347 -u msandbox -p msandbox),
      qw(-D test --check --print-master-server-id)) },
   stderr => 1
);

like(
   $output,
   qr/0\.\d\d\s+12346\n/,
   "--check 12347, automatic source server_id with legacy option"
) or diag($output);

like(
   $output,
   qr/Option --print-master-server-id is deprecated and will be removed in future versions./,
   'Deprecation warning printed for option --print-master-server-id'
) or diag($output);

$output = output(
   sub { pt_heartbeat::main(qw(-h 127.1 -P 12347 -u msandbox -p msandbox),
      qw(-D test --check --print-source-server-id --source-server-id 12346)) },
   stderr => 1
);

like(
   $output,
   qr/0\.\d\d\s+12346\n/,
   "--check 12347 from --source-server-id 12346"
);

$output = output(
   sub { pt_heartbeat::main(qw(-h 127.1 -P 12347 -u msandbox -p msandbox),
      qw(-D test --check --print-source-server-id --master-server-id 12346)) },
   stderr => 1
);

like(
   $output,
   qr/0\.\d\d\s+12346\n/,
   "--check 12347 from --master-server-id 12346"
) or diag($output);

like(
   $output,
   qr/Option --master-server-id is deprecated and will be removed in future versions./,
   'Deprecation warning printed for option --master-server-id'
) or diag($output);

$output = output(
   sub { pt_heartbeat::main(qw(-h 127.1 -P 12347 -u msandbox -p msandbox),
      qw(-D test --check --print-source-server-id --master-server-id 12346),
      qw( --source-server-id 12345)) },
   stderr => 1
);

like(
   $output,
   qr/0\.\d\d\s+12345\n/,
   "--check 12347 from --source-server-id 12345 regardless of --master-server-id 12346"
);

like(
   $output,
   qr/Option --master-server-id is deprecated and will be removed in future versions./,
   'Deprecation warning printed for option --master-server-id'
) or diag($output);

$output = output(
   sub { pt_heartbeat::main(qw(-h 127.1 -P 12347 -u msandbox -p msandbox),
      qw(-D test --check --print-source-server-id --source-server-id 12345)) },
);

sleep 3;
like(
   $output,
   qr/0\.\d\d\s+12345\n/,
   "--check 12347 from --source-server-id 12345"
);

$output = output(
   sub { pt_heartbeat::main(qw(-h 127.1 -P 12347 -u msandbox -p msandbox),
      qw(-D test --check --print-source-server-id --source-server-id 42),
      qw(--no-insert-heartbeat-row)) },
   stderr => 1,
);

like(
   $output,
   qr/No row found in heartbeat table for server_id 42/,
   "Error if --source-server-id row doesn't exist"
);

# ############################################################################
# Stop our --update instances.
# ############################################################################
diag(`$trunk/bin/pt-heartbeat --stop >/dev/null`);
sleep 1;

foreach my $port (@ports) {
   ok(
      !-f "$pid_file.$port",
      "--update on $port stopped"
   );
}

# #############################################################################
# Done.
# #############################################################################
diag(`rm -rf /tmp/pt-heartbeat-sentinel >/dev/null`);
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
