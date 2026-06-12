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

require VersionParser;
use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-duplicate-key-checker";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
else {
   plan tests => 5;
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-duplicate-key-checker -F $cnf -h 127.1 --charset=utf8mb4";

$sb->wipe_clean($dbh);
$sb->create_dbs($dbh, ['test']);

# #############################################################################
# PT-2282: pt-duplicate-key-checker give a "Wide character in print" warning
# #############################################################################
$sb->load_file('source', 't/pt-duplicate-key-checker/samples/pt-2282.sql');
$output = `$cmd -d test -t season_pk_historties_60 `;
unlike(
   $output,
   qr/Wide character in print at/,
   'No "Wide character in print at" error'
);

like(
   $output,
   qr/Total Duplicate Indexes  2/,
   'Number of duplicate indexes reported is correct'
);

like(
   $output,
   qr/Total Indexes            7/,
   'Number of indexes reported is correct'
);

like(
   $output,
   qr/赛程类型/,
   'UTF data printed correctly'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
