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

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 2;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf 127.0.0.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/issue_47.sql');

# #############################################################################
# Issue 8: Add --force-index parameter to mk-table-checksum and mk-table-sync
# #############################################################################

# This is difficult to test. If it works, it should just work silently.
# That is: there's really no way for us to see if MySQL is indeed using
# the index that we told it to.

$output = `MKDEBUG=1 $cmd P=12346 -d test -t issue_47 --algorithm ACCUM 2>&1 | grep 'SQL for chunk 0:'`;
like(
   $output,
   qr/SQL for chunk 0:.*FROM `test`\.`issue_47` (?:FORCE|USE) INDEX \(`idx`\) WHERE/,
   'Injects correct USE INDEX by default'
);

$output = `MKDEBUG=1 $cmd P=12346 -d test -t issue_47 --algorithm ACCUM --no-use-index 2>&1 | grep 'SQL for chunk 0:'`;
like(
   $output,
   qr/SQL for chunk 0:.*FROM `test`\.`issue_47`  WHERE/,
   'Does not inject USE INDEX with --no-use-index'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
