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
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
else {
   plan tests => 8;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

$sb->create_dbs($dbh, ['test']);
$sb->load_file('source', 't/pt-archiver/samples/table1.sql');

# Test basic functionality with defaults
$output = output(
   sub { pt_archiver::main(qw(--where 1=1), "--source", "D=test,t=table_1,F=$cnf", qw(--purge)) },
);
#1
is($output, '', 'Basic test run did not die');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_1"`;
#2
is($output + 0, 0, 'Purged ok');

# Test basic functionality with --commit-each
$sb->load_file('source', 't/pt-archiver/samples/table1.sql');
$output = output(
   sub { pt_archiver::main(qw(--where 1=1), "--source", "D=test,t=table_1,F=$cnf", qw(--commit-each --limit 1 --purge)) },
);
#3
is($output, '', 'Commit-each did not die');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_1"`;
#4
is($output + 0, 0, 'Purged ok with --commit-each');

# Archive only part of the table
$sb->load_file('source', 't/pt-archiver/samples/table1.sql');
$output = output(
   sub { pt_archiver::main(qw(--where 1=1), "--source", "D=test,t=table_1,F=$cnf", qw(--where a<4 --purge)) },
);
#5
is($output, '', 'No output for archiving only part of a table');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_1"`;
#6
is($output + 0, 1, 'Purged some rows ok');

# Fail if --primary-key-only was specified and there is no PK in the table
$sb->load_file('source', 't/pt-archiver/samples/pt_157.sql');
$output = output(
   sub { pt_archiver::main(qw(--where 1=1), "--source", "D=test,t=t1,F=$cnf", qw(--purge --primary-key-only)) },
   stderr => 1,
);
like($output, qr/does not have a PRIMARY KEY/, 'Fail if --primary-key was specified and there is no PK');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
