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

use charnames ':full';

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

my $output;
my $exit_status;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

$sb->wipe_clean($dbh);
$sb->create_dbs($dbh, ['test']);

$sb->load_file('source', 't/pt-archiver/samples/pt-2410.sql');

($output, $exit_status) = full_output(
   sub { pt_archiver::main(
      qw(--where 1=1 --output-format=csv),
      '--source', "L=1,D=pt_2410,t=test,F=$cnf",
      '--file',   '/tmp/pt-2410.csv') },
);

is(
   $exit_status,
   0,
   'pt-archiver comleted'
);

$output = `cat /tmp/pt-2410.csv`;
like(
   $output,
   qr/1,\\N,"testing..."/,
   'NULL values stored correctly'
) or diag($output);

$dbh->do("load data local infile '/tmp/pt-2410.csv' into table pt_2410.test COLUMNS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'");

$output = `/tmp/12345/use pt_2410 -N -e 'SELECT * FROM test'`;

like(
   $output,
   qr/1	NULL	testing.../,
   'NULL values loaded correctly'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -f /tmp/pt-2410.csv`);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
