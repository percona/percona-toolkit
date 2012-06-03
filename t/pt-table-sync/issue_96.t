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
require "$trunk/bin/pt-table-sync";

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

$sb->wipe_clean($master_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 96: mk-table-sync: Nibbler infinite loop
# #############################################################################
diag(`/tmp/12345/use -D test < $trunk/t/lib/samples/issue_96.sql`);
sleep 1;
$output = output(
   sub { pt_table_sync::main('h=127.1,P=12345,u=msandbox,p=msandbox,D=issue_96,t=t', 'h=127.1,P=12345,D=issue_96,t=t2', qw(--algorithms Nibble --chunk-size 2 --print)) },
   trf => \&remove_traces,
);
chomp $output;
is(
   $output,
   "UPDATE `issue_96`.`t2` SET `from_city`='ta' WHERE `package_id`='4' AND `location`='CPR' LIMIT 1;",
   'Sync nibbler infinite loop (issue 96)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
