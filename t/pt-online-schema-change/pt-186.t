#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;

use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir /;

plan tests => 4;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

$sb->load_file('master', "$sample/pt-186.sql");

my $ori_rows = $master_dbh->selectall_arrayref('SELECT * FROM test.t1');

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=t1",
         '--execute', '--no-check-alter', 
         '--alter', 'CHANGE COLUMN `Last_referenced` `c11` INT NOT NULL default 99'
         ),
      },
);

is(
      $exit_status,
      0,
      "--alter rename columns with uppercase names -> exit status 0",
);

my $structure = $master_dbh->selectall_arrayref('DESCRIBE test.t1');
is_deeply(
    $structure->[2],
    [
      'c11',
      'int(11)',
      'NO',
      'MUL',
      '99',
      ''
    ],
    '--alter rename columns with uppercase names -> Column was renamed'
);

my $new_rows = $master_dbh->selectall_arrayref('SELECT * FROM test.t1');

is_deeply(
       $ori_rows,
       $new_rows,
       "--alter rename columns with uppercase names -> Row values OK"
 );
 

$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
