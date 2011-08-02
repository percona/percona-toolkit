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


my $vp = new VersionParser();
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

# Previous tests slave 12347 to 12346 which makes pt-table-checksum
# complain that it cannot connect to 12347 for checking repl filters
# and such.  12347 isn't present but SHOW SLAVE HOSTS on 12346 hasn't
# figured that out yet, so we restart 12346 to refresh this list.
diag(`/tmp/12346/stop >/dev/null`);
diag(`/tmp/12346/start >/dev/null`);
$slave_dbh  = $sb->get_dbh_for('slave1');

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-table-sync -F $cnf"; 
my $t   = qr/\d\d:\d\d:\d\d/;

$sb->wipe_clean($master_dbh);
$sb->load_file('master', 't/pt-table-sync/samples/filter_tables.sql');

$output = `$cmd h=127.1,P=12345 P=12346 --no-check-slave --dry-run -t issue_806_1.t2 | tail -n 2`;
$output =~ s/$t/00:00:00/g;
$output =~ s/[ ]{2,}/ /g;
is(
   $output,
"# DELETE REPLACE INSERT UPDATE ALGORITHM START END EXIT DATABASE.TABLE
# 0 0 0 0 Chunk 00:00:00 00:00:00 0 issue_806_1.t2
",
   "db-qualified --tables (issue 806)"
);

# #############################################################################
# Issue 820: Make mk-table-sync honor schema filters with --replicate
# #############################################################################
$master_dbh->do('DROP DATABASE IF EXISTS test');
$master_dbh->do('CREATE DATABASE test');
$sb->load_file('master', 't/pt-table-sync/samples/checksum_tbl.sql', 'test');

$slave_dbh->do('insert into issue_806_1.t1 values (41)');
$slave_dbh->do('insert into issue_806_2.t2 values (42)');

my $mk_table_checksum = "$trunk/bin/pt-table-checksum";

`$mk_table_checksum -F $cnf --replicate test.checksum h=127.1,P=12345 -d issue_806_1,issue_806_2 --quiet`;
`$mk_table_checksum -F $cnf --replicate test.checksum h=127.1,P=12345 -d issue_806_1,issue_806_2 --replicate-check 1 --quiet`;

$output = `$cmd h=127.1,P=12345 --replicate test.checksum --dry-run | tail -n 2`;
$output =~ s/$t/00:00:00/g;
$output =~ s/[ ]{2,}/ /g;
is(
   $output,
"# 0 0 0 0 Chunk 00:00:00 00:00:00 0 issue_806_2.t2
# 0 0 0 0 Chunk 00:00:00 00:00:00 0 issue_806_1.t1
",
   "--replicate with no filters"
);

$output = `$cmd h=127.1,P=12345 --replicate test.checksum --dry-run -t t1 | tail -n 2`;
$output =~ s/$t/00:00:00/g;
$output =~ s/[ ]{2,}/ /g;
is(
   $output,
"# DELETE REPLACE INSERT UPDATE ALGORITHM START END EXIT DATABASE.TABLE
# 0 0 0 0 Chunk 00:00:00 00:00:00 0 issue_806_1.t1
",
   "--replicate with --tables"
);

$output = `$cmd h=127.1,P=12345 --replicate test.checksum --dry-run -d issue_806_2 | tail -n 2`;
$output =~ s/$t/00:00:00/g;
$output =~ s/[ ]{2,}/ /g;
is(
   $output,
"# DELETE REPLACE INSERT UPDATE ALGORITHM START END EXIT DATABASE.TABLE
# 0 0 0 0 Chunk 00:00:00 00:00:00 0 issue_806_2.t2
",
   "--replicate with --databases"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
