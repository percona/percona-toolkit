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
require "$trunk/bin/pt-table-checksum";

my $vp  = new VersionParser();
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my @args = ('-F', $cnf, 'h=127.1', qw(--explain --replicate test.checksums));

$sb->create_dbs($dbh, [qw(test)]);

# Add a replication filter to the slave.
diag(`/tmp/12346/stop >/dev/null`);
diag(`cp /tmp/12346/my.sandbox.cnf /tmp/12346/orig.cnf`);
diag(`echo "replicate-ignore-db=foo" >> /tmp/12346/my.sandbox.cnf`);
diag(`/tmp/12346/start >/dev/null`);

$output = output(
   sub { pt_table_checksum::main(@args, '--create-replicate-table') },
   stderr => 1,
);
unlike(
   $output,
   qr/mysql\s+user/,
   "Did not checksum with replication filter"
);

like(
   $output,
   qr/replication filters are set/,
   "Warns about replication fitlers"
);

# #############################################################################
# Issue 1060: mk-table-checksum tries to check replicate sanity options
# when no --replicate
# #############################################################################
$output = output(
   sub { pt_table_checksum::main('h=127.1,P=12346,u=msandbox,p=msandbox',
      qw(-d sakila -t film --schema --no-check-replication-filters)) },
);
like(
   $output,
   qr/sakila.+?film/,
   "--schema with replication filters (issue 1060)"
);

# #############################################################################
# Done.
# #############################################################################
# Remove the replication filter from the slave.
diag(`/tmp/12346/stop >/dev/null`);
diag(`mv /tmp/12346/orig.cnf /tmp/12346/my.sandbox.cnf`);
diag(`/tmp/12346/start >/dev/null`);
$sb->wipe_clean($dbh);
exit;
