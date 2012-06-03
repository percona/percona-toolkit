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
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 5;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

$sb->create_dbs($dbh, ['test']);

# Safe auto-increment behavior.
$sb->load_file('master', 't/pt-archiver/samples/table12.sql');
$output = output(
   sub { pt_archiver::main(qw(--purge --where 1=1), "--source", "D=test,t=table_12,F=$cnf") },
);
is($output, '', 'Purge worked OK');
$output = `/tmp/12345/use -N -e "select min(a),count(*) from test.table_12"`;
like($output, qr/^3\t1$/, 'Did not touch the max auto_increment');

# Safe auto-increment behavior, disabled.
$sb->load_file('master', 't/pt-archiver/samples/table12.sql');
$output = output(
   sub { pt_archiver::main(qw(--no-safe-auto-increment --purge --where 1=1), "--source", "D=test,t=table_12,F=$cnf") },
);
is($output, '', 'Disabled safeautoinc worked OK');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_12"`;
is($output + 0, 0, "Disabled safeautoinc purged whole table");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
