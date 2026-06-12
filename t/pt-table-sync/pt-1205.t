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
my $replica2_dbh = $sb->get_dbh_for('replica2'); 

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}
else {
   plan tests => 3;
}

$sb->load_file('source', "t/pt-table-sync/samples/pt-1205.sql");

$sb->wait_for_replicas();

$replica1_dbh->do("DELETE FROM test.t1 LIMIT 3");

# Save original PTDEBUG env because we modify it below.
my $dbg = $ENV{PTDEBUG};

$ENV{PTDEBUG} = 1;
my $output = `$trunk/bin/pt-table-sync h=127.0.0.1,P=12346,u=msandbox,p=msandbox,D=test,t=t1,A=utf8 --sync-to-source --execute --verbose --function=MD5 2>&1`;

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
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
