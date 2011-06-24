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

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

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
   plan tests => 4;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf 127.0.0.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/checksum_tbl.sql');
$sb->load_file('master', 't/pt-table-checksum/samples/resume.sql');
$sb->load_file('master', 't/pt-table-checksum/samples/resume2.sql');

# #############################################################################
# Issue 36: Add --resume option to mk-table-checksum
# #############################################################################

# Test --resume.

# Child processes checksum each db.tbl on each host and print the results
# when done.  So the output is nondeterministic.  sort helps fix this.

$output = `$cmd h=127.1,P=12346 -d test -t resume --chunk-size 3 --chunk-size-limit 0 --resume $trunk/t/pt-table-checksum/samples/resume-chunked-partial.txt | sort | diff $trunk/t/pt-table-checksum/samples/resume-chunked-complete.txt -`;
is(
   $output,
   '',
   '--resume --chunk-size'
);

$output = `$cmd h=127.1,P=12346 -d test -t resume --resume $trunk/t/pt-table-checksum/samples/resume-partial.txt | sort | diff $trunk/t/pt-table-checksum/samples/resume-complete.txt -`;
is(
   $output,
   '',
   '--resume'
);

$output = `$cmd h=127.1,P=12346 -d test,test2 -t resume,resume2 --chunk-size 3 --chunk-size-limit 0 --resume $trunk/t/pt-table-checksum/samples/resume2-chunked-partial.txt | sort | diff $trunk/t/pt-table-checksum/samples/resume2-chunked-complete.txt -`;
is(
   $output,
   '',
   '--resume --chunk-size 2 dbs'
);

# Test --resume-replicate.

# First re-checksum and replicate using chunks so we can more easily break,
# resume and test it.
`$cmd -d test --replicate test.checksum --empty-replicate-table --chunk-size 3 --chunk-size-limit 0`;

# Make sure the results propagate.
sleep 1;

# Now break the results as if that run didn't finish.
`/tmp/12345/use -e "DELETE FROM test.checksum WHERE tbl='resume' AND chunk=2"`;

# And now test --resume with --replicate.
$output = `$cmd -d test --resume-replicate --replicate test.checksum --chunk-size 3 --chunk-size-limit 0`;

# The TIME value can fluctuate between 1 and 0.  Make it 0.
$output =~ s/6abf4a82(\s+)\d+/6abf4a82${1}0/;

is(
   $output,
"DATABASE TABLE  CHUNK HOST      ENGINE      COUNT         CHECKSUM TIME WAIT STAT  LAG
# already checksummed: test resume 0 127.0.0.1
# already checksummed: test resume 1 127.0.0.1
test     resume     2 127.0.0.1 InnoDB          3         6abf4a82    0 NULL NULL NULL
# already checksummed: test resume 3 127.0.0.1
",
   '--resume-replicate'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
