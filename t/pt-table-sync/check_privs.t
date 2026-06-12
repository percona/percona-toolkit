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
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}

$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);

my $output;
my @args = ('h=127.1,P=12345,u=test_907,p=msandbox,s=1', 'P=12346,u=msandbox,s=1', qw(--print --no-check-replica -d issue_907));

# #############################################################################
# Issue 907: Add --[no]check-privileges 
# #############################################################################

#1) get the script to create the underprivileged user  

$source_dbh->do('drop database if exists issue_907');
$source_dbh->do('create database issue_907');
$source_dbh->do('create table issue_907.t (i int)');
PerconaTest::wait_for_table($replica_dbh, "issue_907.t");
$replica_dbh->do('drop database if exists issue_907');
$replica_dbh->do('create database issue_907');
$replica_dbh->do('create table issue_907.t (i int)');
$replica_dbh->do('insert into issue_907.t values (1)');

# On 5.1 user needs SUPER to set binlog_format, which mk-table-sync does.
`/tmp/12345/use -uroot -e "CREATE USER 'test_907'\@'localhost' IDENTIFIED BY 'msandbox'"`;
`/tmp/12345/use -uroot -e "GRANT SUPER, SELECT, UPDATE, SHOW DATABASES ON *.* TO 'test_907'\@'localhost'"`;

#2) run again to see what output is like when it works
chomp($output = output(
   sub { pt_table_sync::main(@args) },
   trf    => \&remove_traces,
));
is(
   $output,
   "DELETE FROM `issue_907`.`t` WHERE `i`='1' LIMIT 1;",
   "Privs are not checked, can --print without extra options"
);

#3) clean up user
$source_dbh->do('DROP USER \'test_907\'@\'localhost\'');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;
