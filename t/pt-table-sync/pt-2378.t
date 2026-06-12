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
   plan tests => 5;
}

my ($output, @rows);

# #############################################################################
# Test generated REPLACE statements.
# #############################################################################
$sb->load_file('source', "t/pt-table-sync/samples/pt-2378.sql");
$sb->wait_for_replicas();
$replica1_dbh->do("update `test`.`test_table` set `some_string` = 'c' where `id` = 1");

$output = remove_traces(output(
   sub { pt_table_sync::main('--sync-to-source',
      'h=127.0.0.1,P=12346,u=msandbox,p=msandbox',
      qw(-t test.test_table --print --execute))
   },
));
chomp($output);
is(
   $output,
   "REPLACE INTO `test`.`test_table`(`id`, `value1`, `value2`, `some_string`) VALUES ('1', 315.25999999999942, 2.6919444444444447, 'a');",
   "Floating point numbers are generated with sufficient precision in REPLACE statements"
);

$sb->wait_for_replicas();
my $query = 'SELECT * FROM `test`.`test_table` WHERE `value1` = 315.2599999999994 AND `value2` = 2.6919444444444447';
@rows = $replica1_dbh->selectrow_array($query);
is_deeply(
   \@rows,
   [1, 315.2599999999994, 2.6919444444444447, 'a'],
   'Floating point values are set correctly in round trip'
);

# #############################################################################
# Test generated UPDATE statements.
# #############################################################################
$sb->load_file('source', "t/pt-table-sync/samples/pt-2378.sql");
$sb->wait_for_replicas();
$replica1_dbh->do("update `test`.`test_table` set `some_string` = 'c' where `id` = 1");

$output = remove_traces(output(
   sub { pt_table_sync::main(qw(--print --execute),
      "h=127.0.0.1,P=12346,u=msandbox,p=msandbox,D=test,t=test_table",
      "h=127.0.0.1,P=12345,u=msandbox,p=msandbox,D=test,t=test_table");
   }
));
chomp($output);
is(
   $output,
   "UPDATE `test`.`test_table` SET `value1`=315.25999999999942, `value2`=2.6919444444444447, `some_string`='c' WHERE `id`='1' LIMIT 1;",
   "Floating point numbers are generated with sufficient precision in UPDATE statements"
);

@rows = $source_dbh->selectrow_array($query);
is_deeply(
   \@rows,
   [1, 315.2599999999994, 2.6919444444444447, 'c'],
   'Floating point values are set correctly in round trip'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
