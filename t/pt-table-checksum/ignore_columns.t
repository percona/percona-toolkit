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
   plan tests => 2;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf 127.0.0.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/issue_94.sql');

# #############################################################################
# Issue 94: Enhance mk-table-checksum, add a --ignore-columns option
# #############################################################################

$output = `$cmd -d test -t issue_94  P=12346 --algorithm ACCUM | awk '{print \$7}'`;
like(
   $output,
   qr/CHECKSUM\n00000006B6BDB8E6\n00000006B6BDB8E6/,
   'Checksum ok with all 3 columns (issue 94 1/2)'
);

$output = `$cmd -d test -t issue_94 P=12346 --algorithm ACCUM --ignore-columns c | awk '{print \$7}'`;
like(
   $output,
   qr/CHECKSUM\n000000066094F8AA\n000000066094F8AA/,
   'Checksum ok with ignored column (issue 94 2/2)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
