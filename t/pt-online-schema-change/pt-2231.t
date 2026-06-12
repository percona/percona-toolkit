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
require "$trunk/bin/pt-online-schema-change";

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
   plan tests => 2;
}

$sb->load_file('source', "t/pt-online-schema-change/samples/basic_no_fks.sql");

$sb->wait_for_replicas();

# Save original PTDEBUG env because we modify it below.
my $dbg = $ENV{PTDEBUG};

$ENV{PTDEBUG} = 1;

my $output = `$trunk/bin/pt-online-schema-change h=localhost,S=/tmp/12345/mysql_sandbox12345.sock,D=pt_osc,t=t --user=msandbox --password=msandbox --replica-user=msandbox --replica-password=msandbox --alter "FORCE" --recursion-method=processlist --no-check-replication-filters --no-check-alter --no-check-plan --chunk-index=PRIMARY --no-version-check --execute 2>&1`;

unlike(
   $output,
   qr/Use of uninitialized value in concatenation (.) or string/,
   'No error with PTDEBUG output'
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
