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
my $slave1_dbh = $sb->get_dbh_for('slave1'); 
my $slave2_dbh = $sb->get_dbh_for('slave2'); 

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}
else {
   plan tests => 3;
}

$sb->load_file('master', "t/pt-table-sync/samples/pt-1205.sql");

$sb->wait_for_slaves();

$slave1_dbh->do("DELETE FROM test.t1 LIMIT 3");

# Save original PTDEBUG env because we modify it below.
my $dbg = $ENV{PTDEBUG};

$ENV{PTDEBUG} = 1;
my $output = `$trunk/bin/pt-table-sync h=127.0.0.1,P=12346,u=msandbox,p=msandbox,D=test,t=t1,A=utf8 --sync-to-master --execute --verbose --function=MD5 2>&1`;

unlike(
   $output,
   qr/Wide character in print at/,
   'Error "Wide character in print at" is not printed for the smiley character'
) or diag($output);

like(
   $output,
   qr/😜/,
   'Smiley character succesfully printed to STDERR'
) or diag($output);

# Restore PTDEBUG env.
delete $ENV{PTDEBUG};
$ENV{PTDEBUG} = $dbg || 0;

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
