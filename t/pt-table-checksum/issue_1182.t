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
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !@{$dbh->selectcol_arrayref('SHOW DATABASES LIKE "sakila"')} ) {
   plan skip_all => 'sakila database is not loaded';
}
else {
   plan tests => 1;
}

my $output;
my $cnf  = '/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf -t sakila.film --chunk-size 100";

# #############################################################################
# Issue 1182: mk-table-checksum not respecting chunk size 
# #############################################################################

# Unfortunately we don't have a good method for testing that the tool
# uses the correct chunks.  That's tested directly in TableChunker.t.
# So here we make sure that --chunk-range doesn't affect anything; it
# should chunk and checksum identically to not using --chunk-range.

diag(`rm -rf /tmp/mk-checksum-test-output-?.txt`);

`$cmd                          >/tmp/mk-table-checksum-test-output-1.txt`;
`$cmd --chunk-range openclosed >/tmp/mk-table-checksum-test-output-2.txt`;

is(
   `diff /tmp/mk-table-checksum-test-output-1.txt /tmp/mk-table-checksum-test-output-2.txt`,
   "",
   "--chunk-range does not alter chunks or checksums"
);

# #############################################################################
# Done.
# #############################################################################
exit;
