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
use Time::HiRes qw(sleep);

$ENV{PTTEST_FAKE_TS} = 1;
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-online-schema-change";
require VersionParser;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}

my $q      = new Quoter();
my $tp     = new TableParser(Quoter => $q);
my @args   = qw(--set-vars innodb_lock_wait_timeout=3);
my $output = "";
my $dsn    = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $exit   = 0;
my $sample = "t/pt-online-schema-change/samples";
my $rows;


# #############################################################################
# Issue 1315130
# Failed to detect child tables in other schema, and falsely identified
# child tables in own schema
# #############################################################################

$sb->load_file('master', "$sample/bug-1315130_cleanup.sql");
$sb->load_file('master', "$sample/bug-1315130.sql");
($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=bug_1315130_a,t=parent_table",
         '--dry-run', 
         '--alter', "add column c varchar(16)",
         '--alter-foreign-keys-method', 'auto'),
      },
);
print STDERR "[$output]\n";
   like(
         $output,
         qr/Child tables:\s*`bug_1315130_a`\.`child_table_in_same_schema` \(approx\. 1 rows\)\s*`bug_1315130_b`\.`child_table_in_second_schema` \(approx\. 1 rows\)[^`]*?Will/s,
         "Correctly identify child tables from other schemas and ignores tables from same schema referencig same named parent in other schema.",
   );
# clear databases with their foreign keys
$sb->load_file('master', "$sample/bug-1315130_cleanup.sql");  

# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
