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

use Data::Dumper;
use PerconaTest;
use Sandbox;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout-3 else the
# tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3 --alter-foreign-keys-method rebuild_constraints));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1215587 
# Adding _ to constraints can create issues with constraint name length
# ############################################################################

$sb->load_file('master', "$sample/bug-1215587.sql");

# run once: we expect constraint names to be prefixed with one underscore
# note: We're running just a neutral no-op alter. We are only interested in constraint name
# changes.
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=bug1215587,t=Table1",
      "--alter", "ENGINE=InnoDB",
      qw(--execute)) },
);


my $constraints = $master_dbh->selectall_hashref("SELECT CONSTRAINT_NAME, TABLE_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE table_schema='bug1215587' and (TABLE_NAME='Table1' OR TABLE_NAME='Table2') and CONSTRAINT_NAME LIKE '%fkey%'", 'table_name'); 


is(
   $constraints->{Table1}->{constraint_name},
   '_fkey1',
   "Altered table: constraint name prefixed one underscore after 1st run"
);

is(
   $constraints->{Table2}->{constraint_name}, 
   '_fkey2',
   "Child table  : constraint name prefixed one underscore after 1st run"
);


# run second time 
# we expect underscores to be removed
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=bug1215587,t=Table1",
      "--alter", "ENGINE=InnoDB",
      qw(--execute)) },
);

$constraints = $master_dbh->selectall_hashref("SELECT CONSTRAINT_NAME, TABLE_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE table_schema='bug1215587' and (TABLE_NAME='Table1' OR TABLE_NAME='Table2') and CONSTRAINT_NAME LIKE '%fkey%'", 'table_name'); 


is(
   $constraints->{'Table1'}->{constraint_name},  
   'fkey1',
   "Altered table: constraint name removed underscore after 2nd run"
);

is(
   $constraints->{'Table2'}->{constraint_name}, 
   'fkey2',
   "Child table  : constraint name removed underscore after 2nd run"
);


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
