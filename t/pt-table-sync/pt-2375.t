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

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
else {
   plan tests => 3;
}

my $output;

# #############################################################################
# Test generated REPLACE statements.
# #############################################################################
$sb->load_file('source', "t/pt-table-sync/samples/pt-2375.sql");
$sb->wait_for_replicas();
$replica1_dbh->do("delete from `test`.`test_table` where `id`=1");

$output = remove_traces(output(
   sub { pt_table_sync::main('--sync-to-source',
      'h=127.0.0.1,P=12346,u=msandbox,p=msandbox',
      qw(-t test.test_table --print --execute))
   },
));
chomp($output);
is(
   $output,
   "REPLACE INTO `test`.`test_table`(`id`, `value`) VALUES ('1', '24');",
   "Generated columns are not used in REPLACE statements"
);

# #############################################################################
# Test generated UPDATE statements.
# #############################################################################
$sb->load_file('source', "t/pt-table-sync/samples/pt-2375.sql");
$sb->wait_for_replicas();
$replica1_dbh->do("update `test`.`test_table` set `value`=55 where `id`=2");

$output = remove_traces(output(
   sub { pt_table_sync::main(qw(--print --execute),
      "h=127.0.0.1,P=12346,u=msandbox,p=msandbox,D=test,t=test_table",
      "h=127.0.0.1,P=12345,u=msandbox,p=msandbox,D=test,t=test_table");
   }
));
chomp($output);
is(
   $output,
   "UPDATE `test`.`test_table` SET `value`='55' WHERE `id`='2' LIMIT 1;",
   "Generated columns are not used in UPDATE statements"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
