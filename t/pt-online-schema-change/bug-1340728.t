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


# #############################################################################
# Issue 1340728
# fails when no index is returned in EXPLAIN,  even though --nocheck-plan is set
# (happens on HASH indexes)
# #############################################################################

$sb->load_file('master', "$sample/bug-1340728_cleanup.sql");
$sb->load_file('master', "$sample/bug-1340728.sql");

# insert a few thousand rows (else test isn't valid)
my $rows = 5000;
for (my $i = 0; $i < $rows; $i++) {
   $master_dbh->do("INSERT INTO bug_1340728.test VALUES (NULL, 'xx')");
}


($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=bug_1340728,t=test",
         '--execute', 
         '--alter', "ADD COLUMN c INT",
         '--nocheck-plan',
         ),
      },
);

   like(
         $output,
         qr/Successfully altered/s,
         "--nocheck-plan ignores plans without index",
   );
# clear databases 
$sb->load_file('master', "$sample/bug-1340728_cleanup.sql");  

# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
