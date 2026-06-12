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

use POSIX qw( tzset );
use File::Temp qw(tempfile);

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

unlink '/tmp/pt-heartbeat-sentinel';
$sb->create_dbs($source_dbh, ['test']);
$sb->wait_for_replicas();

my $output;
my $base_pidfile = (tempfile("/tmp/pt-heartbeat-test.XXXXXXXX", OPEN => 0, UNLINK => 0))[1];
my $source_port = $sb->port_for('source');

my @exec_pids;
my @pidfiles;

sub start_update_instance {
   my ($port) = @_;
   my $pidfile = "$base_pidfile.$port.pid";
   push @pidfiles, $pidfile;

   my $pid = fork();
   if ( $pid == 0 ) {
      my $cmd = "$trunk/bin/pt-heartbeat";
      exec { $cmd } $cmd, qw(-h 127.0.0.1 -u msandbox -p msandbox -P), $port,
                          qw(--database test --table heartbeat --create-table),
                          qw(--utc --update --interval 0.5 --pid), $pidfile;
      exit 1;
   }
   push @exec_pids, $pid;
   
   PerconaTest::wait_for_files($pidfile);
   ok(
      -f $pidfile,
      "--update on $port started"
   );
}

sub stop_all_instances {
   my @pids = @exec_pids, map { chomp; $_ } map { slurp_file($_) } @pidfiles;
   diag(`$trunk/bin/pt-heartbeat --stop >/dev/null`);

   waitpid($_, 0) for @pids;
   PerconaTest::wait_until(sub{ !-e $_ }) for @pidfiles;

   unlink '/tmp/pt-heartbeat-sentinel';
}

# ############################################################################
# pt-heartbeat handles timezones inconsistently
# https://bugs.launchpad.net/percona-toolkit/+bug/886059
# ############################################################################

start_update_instance( $source_port );

PerconaTest::wait_for_table($replica1_dbh, 'test.heartbeat', 'server_id=12345');

my $replica1_dsn = $sb->dsn_for('replica1');
# Using full_output here to work around a Perl bug: Only the first explicit
# tzset works.
($output) = full_output(sub {
   local $ENV{TZ} = '-09:00';
   tzset();
   pt_heartbeat::main($replica1_dsn, qw(--database test --table heartbeat),
                        qw(--utc --check --source-server-id), $source_port)
});

# If the servers use UTC then the lag should be 0.00, or at least
# no greater than 9.99 for slow test boxes.  When this fails, the
# lag is like 25200.00 becaues the servers are hours off.
like(
   $output,
   qr/\A\d.\d{2}$/,
   "--utc bypasses time zone differences (bug 886059, bug 1099665)"
);

stop_all_instances();

# #############################################################################
# pt-heartbeat 2.1.8 doesn't use precision/sub-second timestamps
# https://bugs.launchpad.net/percona-toolkit/+bug/1103221
# #############################################################################

$source_dbh->do('truncate table test.heartbeat');
$sb->wait_for_replicas;

my $source_dsn = $sb->dsn_for('source');

($output) = output(
   sub {
      pt_heartbeat::main($source_dsn, qw(--database test --update),
         qw(--run-time 1))
   },
);

my ($row) = $source_dbh->selectrow_hashref('select * from test.heartbeat');
like(
   $row->{ts},
   qr/\d{4}-\d\d-\d\dT\d+:\d+:\d+\.\d+/,
   "Hi-res timestamp (bug 1103221)"
);


# #############################################################################
# Bug 1163372: pt-heartbeat --utc --check always returns 0
# #############################################################################

my ($sec, $min, $hour, $mday, $mon, $year) = gmtime(time);
$mon  += 1;
$year += 1900;

# Make the ts seem like it 1 hour ago, so the output should show at least
# 1 hour lag, i.e. 1.00, or maybe 1.02 etc. on a slow test box, but definately
# not 0.\d+.
$hour -= 1; 

my $old_utc_ts = sprintf(
   "%d-%02d-%02dT%02d:%02d:%02d",
   $year, $mon, $mday, $hour, $min, $sec);

$source_dbh->do("truncate table test.heartbeat");
$source_dbh->do("insert into test.heartbeat (ts, server_id) values ('$old_utc_ts', 1)");
$sb->wait_for_replicas;

($output) = output(
   sub {
      pt_heartbeat::main(
         $replica1_dsn, qw(--database test --table heartbeat),
         qw(--utc --check --source-server-id), $source_port
      )
   },
);

like(
   $output,
   qr/^1\.\d+/,
   "--utc --check (bug 1163372"
);

# ############################################################################
# Done.
# ############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
