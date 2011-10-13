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

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3)); 
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

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
