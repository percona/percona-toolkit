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
   plan tests => 12;
}

my $output;

# #############################################################################
# PT-2114: Incorrect casting of BIT columns by pt-archiver 
# #############################################################################
$sb->load_file('master', 't/pt-archiver/samples/pt-2114.sql');

my $zero_rows = $dbh->selectall_arrayref('select id, hex(val) from pt_2114.t1 where val = 0');
my $exit_status;

$output = output(
   sub { $exit_status = pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=pt_2114,t=t1,u=msandbox,p=msandbox',
      '--where', '(val) in (select a.val from pt_2114.t1_tmp a where id =2)', 
	  '--purge')
   },
);

is (
    $exit_status,
    0,
    "PT-2114 exit status OK",
);

my $left_rows = $dbh->selectall_arrayref('select id, hex(val) from pt_2114.t1');

is_deeply(
   $zero_rows,
   $left_rows,
   "PT-2114 Only rows with val=0 left in the table"
);

my $count_rows = $dbh->selectrow_arrayref('select count(*) from pt_2114.t1');

is (
   @{$count_rows}[0],
   4,
   "PT-2114 Four rows left in the table"
);

# #############################################################################
# Reloading dump to perform archiving
# #############################################################################
$sb->load_file('master', 't/pt-archiver/samples/pt-2114.sql');

my $one_rows = $dbh->selectall_arrayref('select id, hex(val) from pt_2114.t1 where val = 1');

$output = output(
   sub { $exit_status = pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=pt_2114,t=t1,u=msandbox,p=msandbox',
      '--dest',  'h=127.1,P=12345,D=pt_2114,t=t2,u=msandbox,p=msandbox',
      '--where', '(val) in (select a.val from pt_2114.t1_tmp a where id =2)', 
	  )
   },
);

is (
    $exit_status,
    0,
    "PT-2114 exit status OK",
);

$left_rows = $dbh->selectall_arrayref('select id, hex(val) from pt_2114.t1');

is_deeply(
   $zero_rows,
   $left_rows,
   "PT-2114 Only rows with val=0 left in the table"
);

$count_rows = $dbh->selectrow_arrayref('select count(*) from pt_2114.t1');

is (
   @{$count_rows}[0],
   4,
   "PT-2114 Four rows left in the table"
);

my $archived_rows = $dbh->selectall_arrayref('select id, hex(val) from pt_2114.t2');

is_deeply(
   $one_rows,
   $archived_rows,
   "PT-2114 Correct rows archived"
);

# #############################################################################
# Reloading dump to perform archiving
# #############################################################################
$sb->load_file('master', 't/pt-archiver/samples/pt-2114.sql');

$output = output(
   sub { $exit_status = pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=pt_2114,t=t1,u=msandbox,p=msandbox,L=yes',
      '--dest',  'h=127.1,P=12345,D=pt_2114,t=t2,u=msandbox,p=msandbox,L=yes',
      '--where', '(val) in (select a.val from pt_2114.t1_tmp a where id =2)', 
	  '--bulk-insert', '--limit', '10')
   },
);

is (
    $exit_status,
    0,
    "PT-2114 exit status OK",
);

$left_rows = $dbh->selectall_arrayref('select id, hex(val) from pt_2114.t1');

is_deeply(
   $zero_rows,
   $left_rows,
   "PT-2114 Only rows with val=0 left in the table with --bulk-insert"
);

$count_rows = $dbh->selectrow_arrayref('select count(*) from pt_2114.t1');

is (
   @{$count_rows}[0],
   4,
   "PT-2114 Four rows left in the table"
);

$archived_rows = $dbh->selectall_arrayref('select id, hex(val) from pt_2114.t2');

is_deeply(
   $one_rows,
   $archived_rows,
   "PT-2114 Correct rows archived with --bulk-insert"
);

# TODO
# --bulk-delete with --purge
# --file
# fancy values in BIT column

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
