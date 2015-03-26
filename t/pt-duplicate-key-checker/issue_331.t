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
require "$trunk/bin/pt-duplicate-key-checker";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

my $cnf    = "/tmp/12345/my.sandbox.cnf";
my $sample = "t/pt-duplicate-key-checker/samples/";
my @args   = ('-F', $cnf, qw(-h 127.1));

$sb->wipe_clean($dbh);
$sb->create_dbs($dbh, ['test']);

# #############################################################################
# Issue 331: mk-duplicate-key-checker crashes getting size of foreign keys
# #############################################################################

$sb->load_file('master', 't/pt-duplicate-key-checker/samples/issue_331.sql', 'test');
ok(
   no_diff(
      sub { pt_duplicate_key_checker::main(@args, qw(-d issue_331)) },
      't/pt-duplicate-key-checker/samples/issue_331.txt'
   ),
   'Issue 331 crash on fks'
) or diag($test_diff);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
