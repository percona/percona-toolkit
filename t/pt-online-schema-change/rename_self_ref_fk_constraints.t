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
my $source_dbh = $sb->get_dbh_for('source');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout-3 else the
# tool will die.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3 --alter-foreign-keys-method rebuild_constraints));
my $output;
my $exit_status;

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1632522
# pt-online-schema-change fails with duplicate key in table for self-referencing FK
# ############################################################################

diag("Before loading sql");
$sb->load_file('source', "t/pt-online-schema-change/samples/bug-1632522.sql");
diag("after loading sql");

# run once: we expect the constraint name to be appended with one underscore
# but the self-referencing constraint will have 2 underscore
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=bug1632522,t=test_table",
      "--alter", "ENGINE=InnoDB",
      qw(--execute)) },
);

my $query = <<"END";
  SELECT TABLE_NAME, CONSTRAINT_NAME 
    FROM information_schema.KEY_COLUMN_USAGE 
   WHERE table_schema='bug1632522' 
     AND (TABLE_NAME='test_table' OR TABLE_NAME='person') 
     AND CONSTRAINT_NAME LIKE '%fk_%' 
ORDER BY TABLE_NAME, CONSTRAINT_NAME
END
my $constraints = $source_dbh->selectall_arrayref($query);

is_deeply(
   $constraints,
   [
      ['person', 'fk_testId'],
      ['test_table', 'fk_person'],
      ['test_table', 'fk_refId'],
   ],
   "First run adds or removes underscore from constraint names, accordingly"
);

# run second time: we expect constraint names to be prefixed with one underscore
# if they havre't one, and to remove 2 if they have 2
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=bug1632522,t=test_table",
      "--alter", "ENGINE=InnoDB",
      qw(--execute)) },
);

$query = <<"END";
  SELECT TABLE_NAME, CONSTRAINT_NAME 
    FROM information_schema.KEY_COLUMN_USAGE 
   WHERE table_schema='bug1632522' 
     AND (TABLE_NAME='test_table' OR TABLE_NAME='person') 
     AND CONSTRAINT_NAME LIKE '%fk_%' 
ORDER BY TABLE_NAME, CONSTRAINT_NAME
END
$constraints = $source_dbh->selectall_arrayref($query);


is_deeply(
   $constraints,
   [
      ['person', 'fk_testId'],
      ['test_table', 'fk_person'],
      ['test_table', 'fk_refId'],
   ],
   "Second run self-referencing will be one due to rebuild_constraints"
);

# run third time: we expect constraints to be the same as we started (toggled back)
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=bug1632522,t=test_table",
      "--alter", "ENGINE=InnoDB",
      qw(--execute)) },
);

$query = <<"END";
  SELECT TABLE_NAME, CONSTRAINT_NAME 
    FROM information_schema.KEY_COLUMN_USAGE 
   WHERE table_schema='bug1632522' 
     and (TABLE_NAME='test_table' OR TABLE_NAME='person') 
     and CONSTRAINT_NAME LIKE '%fk_%' 
ORDER BY TABLE_NAME, CONSTRAINT_NAME
END
$constraints = $source_dbh->selectall_arrayref($query);


is_deeply(
   $constraints,
   [
      ['person', 'fk_testId'],
      ['test_table', 'fk_person'],
      ['test_table', 'fk_refId'],
   ],
   "Third run toggles constraint names back to how they were"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
