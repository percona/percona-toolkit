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

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf 127.0.0.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/before.sql');

$output = `$cmd --checksum --ignore-databases sakila -d test -t checksum_test`;
is(
   $output,
   "3036305396        127.0.0.1.test.checksum_test.0
",
   '--checksum terse output'
);

# #############################################################################
# Issue 103: mk-table-checksum doesn't honor --checksum in --schema mode
# #############################################################################
$output = `$cmd --checksum --schema --ignore-databases sakila -d test -t checksum_test`;
unlike(
   $output,
   qr/DATABASE\s+TABLE/,
   '--checksum in --schema mode prints terse output'
);


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
