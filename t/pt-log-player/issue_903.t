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
require "$trunk/bin/pt-log-player";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

# #############################################################################
# Issue 903: mk-log-player --only-select does not handle comments
# #############################################################################

# This should not cause an error because the leading comment
# prevents the query from looking like a SELECT.
my $output;
$output = `$trunk/bin/pt-log-player --threads 1 --play $trunk/t/pt-log-player/samples/issue_903.txt h=127.1,P=12345,u=msandbox,p=msandbox,D=mysql 2>&1`;
like(
   $output,
   qr/caused an error/,
   'Error without --only-select'
);

# This will cause an error now, too, because the leading comment
# is stripped.
$output = `$trunk/bin/pt-log-player --threads 1 --play $trunk/t/pt-log-player/samples/issue_903.txt h=127.1,P=12345,u=msandbox,p=msandbox,D=mysql --only-select 2>&1`;
like(
   $output,
   qr/caused an error/,
   'Error with --only-select'
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -rf ./session-results-*`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
