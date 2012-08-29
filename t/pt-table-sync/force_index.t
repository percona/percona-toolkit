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
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 3;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# ########################################################################
# Issue 8: Add --force-index parameter to mk-table-checksum and
# mk-table-sync
# ########################################################################
$sb->load_file('master', 't/pt-table-sync/samples/issue_37.sql');
$sb->use('master', '-e \'INSERT INTO test.issue_37 VALUES (5), (6), (7), (8), (9);\'');

$output = `PTDEBUG=1 $trunk/bin/pt-table-sync h=127.0.0.1,P=12345,u=msandbox,p=msandbox P=12346 -d test -t issue_37 --algorithms Chunk --chunk-size 3 --no-check-slave --no-check-triggers --print 2>&1 | grep 'src: '`;
like($output, qr/FROM `test`\.`issue_37` FORCE INDEX \(`idx_a`\) WHERE/, 'Injects USE INDEX hint by default');

$output = `PTDEBUG=1 $trunk/bin/pt-table-sync h=127.0.0.1,P=12345,u=msandbox,p=msandbox P=12346 -d test -t issue_37 --algorithms Chunk --chunk-size 3 --no-check-slave --no-check-triggers --no-index-hint --print 2>&1 | grep 'src: '`;
like($output, qr/FROM `test`\.`issue_37`  WHERE/, 'No USE INDEX hint with --no-index-hint');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
