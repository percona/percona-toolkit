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
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

$sb->wipe_clean($dbh);
$sb->create_dbs($dbh, ['test']);

# Test --bulk-insert
$sb->load_file('source', 't/pt-archiver/samples/pt-2279.sql');

$output = output(
   sub { pt_archiver::main(qw(--limit 50 --bulk-insert),
      qw(--bulk-delete --where 1=1 --statistics --charset utf8mb4),
      '--source', "L=1,D=test,t=table_1,F=$cnf",
      '--dest',   "t=table_1_dest") },
);

unlike(
   $output,
   qr/Cannot find encoding "utf8mb4"/,
   'Bulk insert does not fail due to missing utf8mb4'
) or diag($output);

# Test --file
$sb->load_file('source', 't/pt-archiver/samples/pt-2279.sql');

$output = output(
   sub { pt_archiver::main(qw(--limit 50),
      qw(--where 1=1 --statistics --charset utf8mb4),
      '--source', "L=1,D=test,t=table_1,F=$cnf",
      '--file',   '/tmp/%Y-%m-%d-%D_%H:%i:%s.%t') },
);

unlike(
   $output,
   qr/Cannot find encoding "utf8mb4"/,
   'Destination file does not fail due to missing utf8mb4'
) or diag($output);

unlike(
   $output,
   qr/Cannot open :encoding(utf8mb4)/,
   'Destination file can be read if encoding utf8mb4 is used'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -f /tmp/*.table_1`);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
