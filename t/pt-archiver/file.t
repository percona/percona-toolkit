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

use MaatkitTest;
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
$sb->load_file('master', 't/pt-archiver/samples/table1.sql');

# Archive to a file.
`rm -f archive.test.table_1`;
$output = output(
   sub { pt_archiver::main(qw(--where 1=1), "--source", "D=test,t=table_1,F=$cnf", "--file", 'archive.%D.%t') },
);
is($output, '', 'No output for archiving to a file');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_1"`;
is($output + 0, 0, 'Purged all rows ok');
ok(-f 'archive.test.table_1', 'Archive file written OK');
$output = `cat archive.test.table_1`;
is($output, <<EOF
1\t2\t3\t4
2\t\\N\t3\t4
3\t2\t3\t\\\t
4\t2\t3\t\\

EOF
, 'File has the right stuff');
`rm -f archive.test.table_1`;

# Archive to a file, but specify only some columns.
$sb->load_file('master', 't/pt-archiver/samples/table1.sql');
`rm -f archive.test.table_1`;
$output = output(
   sub { pt_archiver::main("-c", "b,c", qw(--where 1=1 --header), "--source", "D=test,t=table_1,F=$cnf", "--file", 'archive.%D.%t') },
);
$output = `cat archive.test.table_1`;
is($output, <<EOF
b\tc
2\t3
\\N\t3
2\t3
2\t3
EOF
, 'File has the right stuff with only some columns');
`rm -f archive.test.table_1`;

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
