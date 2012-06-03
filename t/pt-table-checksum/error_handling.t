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
shift @INC;  # our unshift (above)
shift @INC;  # PerconaTest's unshift
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 7;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3), '--max-load', ''); 
my $output;

$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 81: put some data that's too big into the boundaries table
# #############################################################################
$sb->load_file('master', 't/pt-table-checksum/samples/checksum_tbl_truncated.sql');

$output = output(
   sub { pt_table_checksum::main(@args,
      qw(--replicate test.truncated_checksums -t sakila.film_category),
      qw(--chunk-time 0 --chunk-size 100) ) },
   stderr => 1,
);

like(
   $output,
   qr/MySQL error 1265: Data truncated/,
   "MySQL error 1265: Data truncated for column"
);

my (@errors) = $output =~ m/error/;
is(
   scalar @errors,
   1,
   "Only one warning for MySQL error 1265"
);

# ############################################################################
# Lock wait timeout
# ############################################################################
$master_dbh->do('use sakila');
$master_dbh->do('begin');
$master_dbh->do('select * from city for update');

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.city)) },
   stderr => 1,
   trf    => sub { return PerconaTest::normalize_checksum_results(@_) },
);

like(
   $output,
   qr/Lock wait timeout exceeded/,
   "Catches lock wait timeout"
);

like(
   $output,
   qr/^0 0 0 1 1 sakila.city/m,
   "Skips chunk that times out"
);

# Lock wait timeout for sandbox servers is 3s, so sleep 4 then commit
# to release the lock.  That should allow the checksum query to finish.
my ($id) = $master_dbh->selectrow_array('select connection_id()');
system("sleep 4 ; /tmp/12345/use -e 'KILL $id' >/dev/null");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.city)) },
   stderr => 1,
   trf    => sub { return PerconaTest::normalize_checksum_results(@_) },
);

unlike(
   $output,
   qr/Lock wait timeout exceeded/,
   "Lock wait timeout retried"
);

like(
   $output,
   qr/^0 0 600 1 0 sakila.city/m,
   "Checksum retried after lock wait timeout"
);

# Reconnect to master since we just killed ourself.
$master_dbh = $sb->get_dbh_for('master');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
