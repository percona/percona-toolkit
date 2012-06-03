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
   plan tests => 2;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 262
# #############################################################################
$sb->create_dbs($master_dbh, ['foo']);
$sb->use('master', '-e "create table foo.t1 (i int)"');
$sb->use('master', '-e "SET SQL_LOG_BIN=0; insert into foo.t1 values (1)"');
$sb->use('slave1', '-e "truncate table foo.t1"');
$output = `$trunk/bin/pt-table-sync --no-check-slave --print h=127.1,P=12345,u=msandbox,p=msandbox -d mysql,foo h=127.1,P=12346 2>&1`;
like(
   $output,
   qr/INSERT INTO `foo`\.`t1`\(`i`\) VALUES \('1'\)/,
   'Does not die checking tables for triggers (issue 262)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
