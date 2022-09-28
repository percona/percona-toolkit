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
$master_dbh->do('SET @@collation_server="latin1_swedish_ci"');
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox,charset=utf8';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3 --alter-foreign-keys-method rebuild_constraints));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1215587 
# Adding _ to constraints can create issues with constraint name length
# ############################################################################

$sb->load_file('master', "$sample/long_fk_constraints.sql");

# run once: we expect constraint names to be prefixed with one underscore
# if they havre't one, and to remove 2 if they have 2
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=bug1215587,t=Table1",
      "--alter", "ENGINE=InnoDB",
      "--charset", "utf8",
      qw(--execute)) },
);

my $query = <<_SQL;
  SELECT TABLE_NAME, CONSTRAINT_NAME 
    FROM information_schema.KEY_COLUMN_USAGE 
   WHERE table_schema='bug1215587' 
     and (TABLE_NAME='Table1' OR TABLE_NAME='Table2') 
     and CONSTRAINT_NAME LIKE '%fkey%' 
ORDER BY TABLE_NAME, CONSTRAINT_NAME
_SQL
my $constraints = $master_dbh->selectall_arrayref($query); 

# why we need to sort? Depending on the MySQL version and the characters set, the ORDER BY clause
# in the query will return different values so, it is better to rely on our own sorted results.
my @sorted_constraints = sort { @$a[0].@$a[1] cmp @$b[0].@$b[1] } @$constraints;
is_deeply(
   \@sorted_constraints,
   [
    [ 'Table1', '_fkey1a' ],
    [ 'Table1', '_fkey_SALES_RECURRING_PROFILE_CUSTOMER_CUSTOMER_ENTITY_ENTITY_ID' ],
    [ 'Table2', '_fkey2b' ],
    [ 'Table2', 'fkey2a' ],
   ],
   "First run adds or removes underscore from constraint names, accordingly"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
