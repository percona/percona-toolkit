#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More ;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-slave-delay";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('source');
my $slave1_dbh  = $sb->get_dbh_for('replica1');
my $slave2_dbh  = $sb->get_dbh_for('replica2');

if ($sandbox_version lt '8.1') {
   plan skip_all => 'Tool is supported.';
}

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}
else {
   plan tests => 3;
}

my $output;
my $cnf = '/tmp/12346/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-slave-delay -F $cnf h=127.1";

$output = `$cmd 2>&1`;
like(
   $output, 
   qr/This tool does not work with MySQL 8.1 and newer/, 
   'The tool does not work with 8.1 or newer'
);

isnt(
   $? >> 8,
   0,
   "Tool died"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
