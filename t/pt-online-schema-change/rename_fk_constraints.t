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

my $vp = VersionParser->new($source_dbh);

if ($vp->cmp('8.0') > -1 && $vp->cmp('8.0.14') < 0 && $vp->flavor() !~ m/maria/i) {
   plan skip_all => 'Cannot run this test under the current MySQL version';
}

if ( !$source_dbh  && $vp->flavor() !~ m/maria/i) {
   plan skip_all => 'Cannot connect to sandbox source';
}

my $old_restrict_fk_on_non_standard_key;

if ( $sandbox_version ge '8.4' ){
   $old_restrict_fk_on_non_standard_key = ($source_dbh->selectrow_array('SELECT @@RESTRICT_FK_ON_NON_STANDARD_KEY'))[0];
   $source_dbh->do('SET GLOBAL RESTRICT_FK_ON_NON_STANDARD_KEY = 0');
}
# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout-3 else the
# tool will die.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3 --alter-foreign-keys-method rebuild_constraints));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1215587 
# Adding _ to constraints can create issues with constraint name length
# ############################################################################

$sb->load_file('source', "$sample/bug-1215587.sql");

# run once: we expect constraint names to be prefixed with one underscore
# if they havre't one, and to remove 2 if they have 2
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=bug1215587,t=Table1",
      "--alter", "ENGINE=InnoDB",
      qw(--execute)) },
);

my $query = <<__SQL;
  SELECT TABLE_NAME, CONSTRAINT_NAME 
    FROM information_schema.KEY_COLUMN_USAGE 
   WHERE table_schema='bug1215587' 
     and (TABLE_NAME='Table1' OR TABLE_NAME='Table2') 
     and CONSTRAINT_NAME LIKE '%fkey%' 
ORDER BY TABLE_NAME, CONSTRAINT_NAME 
__SQL

my $constraints = $source_dbh->selectall_arrayref($query); 
# why we need to sort? Depending on the MySQL version and the characters set, the ORDER BY clause
# in the query will return different values so, it is better to rely on our own sorted results.
my @sorted_constraints = sort { @$a[0].@$a[1] cmp @$b[0].@$b[1] } @$constraints;

is_deeply(
   \@sorted_constraints,
   [
      ['Table1', '__fkey1a'],
      ['Table1', '_fkey1b'],
      ['Table2', '__fkey2b'],
      ['Table2', '_fkey2a'],
   ],
   "First run adds or removes underscore from constraint names, accordingly"
);

# run second time: we expect constraint names to be prefixed with one underscore
# if they havre't one, and to remove 2 if they have 2
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=bug1215587,t=Table1",
      "--alter", "ENGINE=InnoDB",
      qw(--execute)) },
);

$constraints = $source_dbh->selectall_arrayref("SELECT TABLE_NAME, CONSTRAINT_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE table_schema='bug1215587' and (TABLE_NAME='Table1' OR TABLE_NAME='Table2') and CONSTRAINT_NAME LIKE '%fkey%' ORDER BY TABLE_NAME, CONSTRAINT_NAME"); 
@sorted_constraints = sort { @$a[0].@$a[1] cmp @$b[0].@$b[1] } @$constraints; # read above why we need to sort

is_deeply(
   \@sorted_constraints,
   [
      ['Table1', '__fkey1b'],
      ['Table1', 'fkey1a'],
      ['Table2', '__fkey2a'],
      ['Table2', 'fkey2b'],
   ],
   "Second run adds or removes underscore from constraint names, accordingly"
);

# run third time: we expect constraints to be the same as we started (toggled back)
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=bug1215587,t=Table1",
      "--alter", "ENGINE=InnoDB",
      qw(--execute)) },
);

$constraints = $source_dbh->selectall_arrayref("SELECT TABLE_NAME, CONSTRAINT_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE table_schema='bug1215587' and (TABLE_NAME='Table1' OR TABLE_NAME='Table2') and CONSTRAINT_NAME LIKE '%fkey%' ORDER BY TABLE_NAME, CONSTRAINT_NAME"); 
@sorted_constraints = sort { @$a[0].@$a[1] cmp @$b[0].@$b[1] } @$constraints; # read above why we need to sort

is_deeply(
   \@sorted_constraints,
   [
      ['Table1', '_fkey1a'],
      ['Table1', 'fkey1b'],
      ['Table2', '_fkey2b'],
      ['Table2', 'fkey2a'],
   ],
   "Third run toggles constraint names back to how they were"
);

# #############################################################################
# Done.
# #############################################################################
if ( $sandbox_version ge '8.4' ){
   $source_dbh->do("SET GLOBAL RESTRICT_FK_ON_NON_STANDARD_KEY = $old_restrict_fk_on_non_standard_key");
}

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
