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
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);

my $output;
my @args = ('h=127.1,P=12345,u=test_907,p=msandbox', 'P=12346,u=msandbox', qw(--print --no-check-slave -d issue_907));

# #############################################################################
# Issue 907: Add --[no]check-privileges 
# #############################################################################

#1) get the script to create the underprivileged user  

$master_dbh->do('drop database if exists issue_907');
$master_dbh->do('create database issue_907');
$master_dbh->do('create table issue_907.t (i int)');
PerconaTest::wait_for_table($slave_dbh, "issue_907.t");
$slave_dbh->do('drop database if exists issue_907');
$slave_dbh->do('create database issue_907');
$slave_dbh->do('create table issue_907.t (i int)');
$slave_dbh->do('insert into issue_907.t values (1)');

# On 5.1 user needs SUPER to set binlog_format, which mk-table-sync does.
`/tmp/12345/use -uroot -e "GRANT SUPER, SELECT, SHOW DATABASES ON *.* TO 'test_907'\@'localhost' IDENTIFIED BY 'msandbox'"`;

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
$master_dbh->do('DROP USER \'test_907\'@\'localhost\'');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;
