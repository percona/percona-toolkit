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

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave2_dbh = $sb->get_dbh_for('slave2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}
else {
   plan tests => 4;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3), '--max-load', '');
my $output;
my $row;

# Add a replication filter to the slaves.
for my $port ( qw(12346 12347) ) {
   diag(`/tmp/$port/stop >/dev/null`);
   diag(`cp /tmp/$port/my.sandbox.cnf /tmp/$port/orig.cnf`);
   diag(`echo "replicate-ignore-db=foo" >> /tmp/$port/my.sandbox.cnf`);
   diag(`/tmp/$port/start >/dev/null`);
}

my $pos = PerconaTest::get_master_binlog_pos($master_dbh);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.country)) },
   stderr => 1,
);

is(
   PerconaTest::get_master_binlog_pos($master_dbh),
   $pos,
   "Did not checksum with replication filter"
);

like(
   $output,
   qr/h=127.0.0.1,P=12346/,
   "Warns about replication fitler on slave1"
);

like(
   $output,
   qr/h=127.0.0.1,P=12347/,
   "Warns about replication fitler on slave2"
);

# Disable the check.
$output = output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.country),
      qw(--no-check-replication-filters)) },
   stderr => 1,
);

like(
   $output,
   qr/sakila\.country$/,
   "--no-check-replication-filters"
);

# #############################################################################
# Done.
# #############################################################################
# Remove the replication filter from the slave.
for my $port ( qw(12346 12347) ) {
   diag(`/tmp/$port/stop >/dev/null`);
   diag(`mv /tmp/$port/orig.cnf /tmp/$port/my.sandbox.cnf`);
   diag(`/tmp/$port/start >/dev/null`);
}
$sb->wipe_clean($master_dbh);
exit;
