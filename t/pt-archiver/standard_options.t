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

my $dp   = new DSNParser(opts=>$dsn_opts);
my $sb   = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh  = $sb->get_dbh_for('master');
my $dbh2 = $sb->get_dbh_for('slave1');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$dbh2 ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}

my $output;
my $cnf      = "/tmp/12345/my.sandbox.cnf";
my $pid_file = "/tmp/pt-archiver-test.pid.$PID";
my $sentinel = "/tmp/pt-archiver-test.sentinel.$PID";

$sb->create_dbs($dbh, [qw(test)]);

ok(
   no_diff(
      sub {
         pt_archiver::main('--source', "F=$cnf,h=127.1,D=sakila,t=film",
            qw(--no-check-charset --purge --dry-run --port 12345),
            "--where", "film_id < 100")
      },
      "t/pt-archiver/samples/issue-248.txt",
   ),
   'DSNs inherit from standard connection options (issue 248)'
);

# Test with a sentinel file
$sb->load_file('master', 't/pt-archiver/samples/table1.sql');
diag(`touch $sentinel`);

$output = output(
   sub { pt_archiver::main("--source", "D=test,t=table_1,F=$cnf",
      qw(--where 1=1 --why-quit --purge),
      "--sentinel", $sentinel)
   },
   stderr => 1,
);

like(
   $output,
   qr/because sentinel file $sentinel exists/,
   'Exits because of sentinel'
);

$output = `/tmp/12345/use -N -e "select count(*) from test.table_1"`;
is(
   $output + 0,
   4,
   'No rows were deleted'
) or diag($output);

diag(`rm -f $sentinel`);

# Test --stop, which sets the sentinel
$output = output(
   sub { pt_archiver::main("--sentinel", $sentinel, "--stop") },
);

like(
   $output,
   qr/Successfully created file $sentinel/,
   'Created the sentinel OK'
);

diag(`rm -f $sentinel`);

# #############################################################################
# Issue 391: Add --pid option to mk-table-sync
# #############################################################################
diag(`touch $pid_file`);

$output = output(
   sub { pt_archiver::main('--source', "F=$cnf,D=test,t=issue_131_src",
      qw(--where 1=1 --statistics --dest t=issue_131_dst),
      "--pid", $pid_file)
   },
   stderr => 1,
);

like(
   $output,
   qr{PID file $pid_file already exists},
   'Dies if PID file already exists (issue 391)'
);

diag(`rm -f $pid_file`);

# #############################################################################
# Issue 460: mk-archiver does not inherit DSN as documented 
# #############################################################################

# This test will achive rows from dbh:test.table_1 to dbh2:test.table_2.
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');

# Change passwords so defaults files won't work.
$sb->do_as_root(
   'master',
   q/CREATE USER 'bob'@'%' IDENTIFIED BY 'foo'/,
   q/GRANT ALL ON *.* TO 'bob'@'%'/,
);
$dbh2->do('TRUNCATE TABLE test.table_2');
$sb->wait_for_slaves;

$output = output(
   sub { pt_archiver::main(
      '--source', 'h=127.1,P=12345,D=test,t=table_1,u=bob,p=foo',
      '--dest',   'P=12346,t=table_2',
      qw(--where 1=1))
   },
   stderr => 1,
);

my $r = $dbh2->selectall_arrayref('SELECT * FROM test.table_2');
is(
   scalar @$r,
   4,
   '--dest inherited from --source'
);

$sb->do_as_root('master', q/DROP USER 'bob'@'%'/);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
