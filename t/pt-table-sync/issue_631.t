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
   plan tests => 3;
}

$sb->wipe_clean($master_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 631: mk-table-sync GroupBy and Stream fail
# #############################################################################
diag(`/tmp/12345/use < $trunk/t/pt-table-sync/samples/issue_631.sql`);

$output = output(
   sub { pt_table_sync::main('h=127.1,P=12345,u=msandbox,p=msandbox,D=d1,t=t', 'h=127.1,P=12345,D=d2,t=t', 'h=127.1,P=12345,D=d3,t=t', qw(--print -v --algorithms GroupBy)) },
   trf => \&remove_traces,
);
$output =~ s/\d\d:\d\d:\d\d/00:00:00/g;
ok(
   no_diff(
      $output,
      "t/pt-table-sync/samples/issue_631_output_1.txt",
      cmd_output => 1,
   ),
   'GroupBy can sync issue 631'
);

$output = output(
   sub { pt_table_sync::main('h=127.1,P=12345,u=msandbox,p=msandbox,D=d1,t=t', 'h=127.1,P=12345,D=d2,t=t', 'h=127.1,P=12345,D=d3,t=t', qw(--print -v --algorithms Stream)) },
   trf => \&remove_traces,
);
$output =~ s/\d\d:\d\d:\d\d/00:00:00/g;
ok(
   no_diff(
      $output,
      "t/pt-table-sync/samples/issue_631_output_2.txt",
      cmd_output => 1,
   ),
   'Stream can sync issue 631'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
