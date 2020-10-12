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

plan tests => 3;

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
my $ERROR_UPDATING_FKS = 15; # from pt-online-schema-change line 8453

$sb->load_file('master', "$sample/pt-169.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=users",
         '--execute', '--alter', 'CHANGE COLUMN id id BIGINT UNSIGNED NOT NULL FIRST', 
         '--set-vars', 'foreign_key_checks=0',
         '--alter-foreign-keys-method', 'drop_swap',  '--no-check-alter')
      },
);

is(
      $exit_status,
      $ERROR_UPDATING_FKS,
      "--alter rename columns with uppercase names -> exit status 0",
);

# Since drop_swap has failed, the clueanup process should be skipped and the new table
# shouldn't be deleted
my $row = $master_dbh->selectrow_hashref("select count(*) AS how_many from test._users_new");
is (
    $row->{how_many},
    1,
    "Correct number of rows",
);

$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
