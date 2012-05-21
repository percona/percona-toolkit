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
   plan tests => 8;
}

# Previous tests slave 12347 to 12346 which makes pt-table-checksum
# complain that it cannot connect to 12347 for checking repl filters
# and such.  12347 isn't present but SHOW SLAVE HOSTS on 12346 hasn't
# figured that out yet, so we restart 12346 to refresh this list.
#diag(`/tmp/12346/stop >/dev/null`);
#diag(`/tmp/12346/start >/dev/null`);
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

$slave_dbh->do('insert into issue_806_1.t1 values (41)');
$slave_dbh->do('insert into issue_806_2.t2 values (42)');

my $mk_table_checksum = "$trunk/bin/pt-table-checksum --lock-wait-time 3";

`$mk_table_checksum --replicate test.checksum h=127.1,P=12345,u=msandbox,p=msandbox -d issue_806_1,issue_806_2 --quiet`;

$output = `$cmd h=127.1,P=12345 --replicate test.checksum --dry-run | tail -n 2`;
$output =~ s/$t/00:00:00/g;
$output =~ s/[ ]{2,}/ /g;
is(
   $output,
"# 0 0 0 0 Chunk 00:00:00 00:00:00 0 issue_806_1.t1
# 0 0 0 0 Chunk 00:00:00 00:00:00 0 issue_806_2.t2
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
# pt-table-sync --ignore-* options don't work with --replicate 
# https://bugs.launchpad.net/percona-toolkit/+bug/1002365
# #############################################################################
$sb->wipe_clean($master_dbh);

$sb->load_file("master", "t/pt-table-sync/samples/simple-tbls.sql");
PerconaTest::wait_for_table($slave_dbh, "test.mt1", "id=10");

# Create a checksum diff in a table that we're going to ignore
# when we sync.
$slave_dbh->do("INSERT INTO test.empty_it VALUES (null,11,11,'eleven')");

# Create the checksums.
diag(`$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox -d test --quiet --quiet --lock-wait-timeout 3 --max-load ''`);

# Make sure all the tables were checksummed.
my $rows = $master_dbh->selectall_arrayref("SELECT DISTINCT db, tbl FROM percona.checksums ORDER BY db, tbl");
is_deeply(
   $rows,
   [ [qw(test empty_it) ],
     [qw(test empty_mt) ],
     [qw(test it1) ],
     [qw(test it2) ],
     [qw(test mt1) ],
     [qw(test mt2) ],
   ],
   "Six checksum tables (bug 1002365)"
);

# Sync the checksummed tables, but ignore the table with the diff we created.
$output = output(
   sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
      qw(--print --sync-to-master --replicate percona.checksums),
      "--ignore-tables", "test.empty_it") },
   stderr => 1,
);

is(
   $output,
   "",
   "Table ignored, nothing to sync (bug 1002365)"
);

# Sync the checksummed tables, but ignore the database.
$output = output(
   sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
      qw(--print --sync-to-master --replicate percona.checksums),
      "--ignore-databases", "test") },
   stderr => 1,
);

is(
   $output,
   "",
   "Database ignored, nothing to sync (bug 1002365)"
);

# The same should work for just --sync-to-master.
$output = output(
   sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
      qw(--print --sync-to-master),
      "--ignore-tables", "test.empty_it",
      "--ignore-databases", "percona") },
   stderr => 1,
);

unlike(
   $output,
   qr/empty_it/,
   "Table ignored, nothing to sync-to-master (bug 1002365)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
