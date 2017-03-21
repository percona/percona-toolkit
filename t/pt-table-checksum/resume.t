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
my $slave1_dbh = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 48;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my $row;
my $output;

sub load_data_infile {
   my ($file, $where) = @_;
   $master_dbh->do('truncate table percona.checksums');
   $master_dbh->do("LOAD DATA LOCAL INFILE '$trunk/t/pt-table-checksum/samples/checksum_results/$file' INTO TABLE percona.checksums");
   if ( $where ) {
      PerconaTest::wait_for_table($slave1_dbh, 'percona.checksums', $where);
   }
}

# Create an empty replicate table.
pt_table_checksum::main(@args, qw(-d foo --quiet));
PerconaTest::wait_for_table($slave1_dbh, 'percona.checksums');
$master_dbh->do('truncate table percona.checksums');

my $all_sakila_tables =  [
   [qw( sakila actor        )],
   [qw( sakila address      )],
   [qw( sakila category     )],
   [qw( sakila city         )],
   [qw( sakila country      )],
   [qw( sakila customer     )],
   [qw( sakila film         )],
   [qw( sakila film_actor   )],
   [qw( sakila film_category)],
   [qw( sakila film_text    )],
   [qw( sakila inventory    )],
   [qw( sakila language     )],
   [qw( sakila payment      )],
   [qw( sakila rental       )],
   [qw( sakila staff        )],
   [qw( sakila store        )],
];

# ############################################################################
# "Resume" from empty repl table.
# ############################################################################

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d sakila --resume --chunk-size 10000)) },
);

$row = $master_dbh->selectall_arrayref('select db, tbl from percona.checksums order by db, tbl');

is_deeply(
   $row,
   $all_sakila_tables,
   "Resume from empty repl table"
);

# ############################################################################
# Resume when all tables already done.
# ############################################################################

# Timestamps shouldn't change because no rows should be updated.
$row = $master_dbh->selectall_arrayref('select ts from percona.checksums order by db, tbl');

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d sakila --resume)) },
);

is(
   $output,
   "",
   "Resume with nothing to do"
);

is_deeply(
   $master_dbh->selectall_arrayref('select ts from percona.checksums order by db, tbl'),
   $row,
   "Timestamps didn't change"
);

# ############################################################################
# Resume from a single chunk table.  So, resume should really start with
# next table.
# ############################################################################
load_data_infile("sakila-done-singles", "ts='2011-10-15 13:00:16'");
$master_dbh->do("delete from percona.checksums where ts > '2011-10-15 13:00:04'");

$row = $master_dbh->selectall_arrayref('select db, tbl from percona.checksums order by db, tbl');
is_deeply(
   $row,
   [
      [qw( sakila actor         )],
      [qw( sakila address       )],
      [qw( sakila category      )],
      [qw( sakila city          )],
   ],
   "Checksum results for 1/4 of sakila singles"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d sakila --resume --chunk-size 10000)) },
);

$row = $master_dbh->selectall_arrayref('select db, tbl from percona.checksums order by db, tbl');
is_deeply(
   $row,
   $all_sakila_tables,
   "Resume finished sakila"
);

my (undef, $first_tbl) = split /\n/, $output;
like(
   $first_tbl,
   qr/sakila.country$/,
   "Resumed from next table"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "Resumed 0 errors"
);

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   0,
   "Resumed 0 diffs"
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   45_854,
   "Resumed 45,854 rows"
);

# ############################################################################
# Resume from the middle of a table that was being chunked.
# ############################################################################
load_data_infile("sakila-done-1k-chunks", "ts='2011-10-15 13:00:57'");
$master_dbh->do("delete from percona.checksums where ts > '2011-10-15 13:00:28'");

my $first_half = [
   [qw(sakila actor 1 200 )],
   [qw(sakila address 1 603 )],
   [qw(sakila category 1 16 )],
   [qw(sakila city 1 600 )],
   [qw(sakila country 1 109 )],
   [qw(sakila customer 1 599 )],
   [qw(sakila film 1 1000 )],
   [qw(sakila film_actor 1 1000 )],
   [qw(sakila film_actor 2 1000 )],
   [qw(sakila film_actor 3 1000 )],
   [qw(sakila film_actor 4 1000 )],
   [qw(sakila film_actor 5 1000 )],
   [qw(sakila film_actor 6 462 )],
   [qw(sakila film_actor 7 0   )], # lower oob
   [qw(sakila film_actor 8 0   )], # upper oob
   [qw(sakila film_category 1 1000 )],
   [qw(sakila film_text 1 1000 )],
   [qw(sakila inventory 1 1000 )],
   [qw(sakila inventory 2 1000 )],
   [qw(sakila inventory 3 1000 )],
   [qw(sakila inventory 4 1000 )],
   [qw(sakila inventory 5 581 )],
   [qw(sakila inventory 6 0   )], # lower oob
   [qw(sakila inventory 7 0   )], # upper oob
   [qw(sakila language 1 6 )],
   [qw(sakila payment 1 1000 )],
   [qw(sakila payment 2 1000 )],
   [qw(sakila payment 3 1000 )],
   [qw(sakila payment 4 1000 )],
   [qw(sakila payment 5 1000 )],
   [qw(sakila payment 6 1000 )],
   [qw(sakila payment 7 1000 )],
];
my $second_half = [
   [qw(sakila payment 8 1000 )],
   [qw(sakila payment 9 1000 )],
   [qw(sakila payment 10 1000 )],
   [qw(sakila payment 11 1000 )],
   [qw(sakila payment 12 1000 )],
   [qw(sakila payment 13 1000 )],
   [qw(sakila payment 14 1000 )],
   [qw(sakila payment 15 1000 )],
   [qw(sakila payment 16 1000 )],
   [qw(sakila payment 17 49   )],
   [qw(sakila payment 18 0    )], # lower oob
   [qw(sakila payment 19 0  )],   # upper oob
   [qw(sakila rental 1 1000 )],
   [qw(sakila rental 2 1000 )],
   [qw(sakila rental 3 1000 )],
   [qw(sakila rental 4 1000 )],
   [qw(sakila rental 5 1000 )],
   [qw(sakila rental 6 1000 )],
   [qw(sakila rental 7 1000 )],
   [qw(sakila rental 8 1000 )],
   [qw(sakila rental 9 1000 )],
   [qw(sakila rental 10 1000 )],
   [qw(sakila rental 11 1000 )],
   [qw(sakila rental 12 1000 )],
   [qw(sakila rental 13 1000 )],
   [qw(sakila rental 14 1000 )],
   [qw(sakila rental 15 1000 )],
   [qw(sakila rental 16 1000 )],
   [qw(sakila rental 17 44 )],
   [qw(sakila rental 18 0  )], # lower oob
   [qw(sakila rental 19 0  )], # upper oob
   [qw(sakila staff 1 2 )],
   [qw(sakila store 1 2 )],
];

$row = $master_dbh->selectall_arrayref('select db, tbl, chunk, master_cnt from percona.checksums order by db, tbl');
is_deeply(
   $row,
   $first_half,
   "Checksum results through sakila.payment chunk 7"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d sakila --resume),
      qw(--chunk-time 0)) },
);

$row = $master_dbh->selectall_arrayref('select db, tbl, chunk, master_cnt from percona.checksums order by db, tbl');
is_deeply(
   $row,
   [
      @$first_half,
      @$second_half,
   ],
   "Resume finished sakila"
);

(undef, undef, $first_tbl) = split /\n/, $output;
like(
   $first_tbl,
   qr/sakila.payment$/,
   "Resumed from sakila.payment"
);

like(
   $output,
   qr/^Resuming from sakila.payment chunk 7, timestamp 2011-10-15 13:00:28\n/,
    "Resumed from sakila.payment chunk 7"  
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "Resumed 0 errors"
);

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   0,
   "Resumed 0 diffs"
);

is(
   PerconaTest::count_checksum_results($output, 'skipped'),
   0,
   "Resumed 0 skipped"
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   25_097,
   "Resumed 25,097 rows"
);

# ############################################################################
# Resume from the end of a finished table that was being chunked.
# ############################################################################
load_data_infile("sakila-done-1k-chunks", "ts='2011-10-15 13:00:57'");
$master_dbh->do("delete from percona.checksums where ts > '2011-10-15 13:00:38'");

$row = $master_dbh->selectall_arrayref('select db, tbl, chunk, master_cnt from percona.checksums order by db, tbl');
is_deeply(
   $row,
   [
      @$first_half,
      [qw(sakila payment 8 1000 )],
      [qw(sakila payment 9 1000 )],
      [qw(sakila payment 10 1000 )],
      [qw(sakila payment 11 1000 )],
      [qw(sakila payment 12 1000 )],
      [qw(sakila payment 13 1000 )],
      [qw(sakila payment 14 1000 )],
      [qw(sakila payment 15 1000 )],
      [qw(sakila payment 16 1000 )],
      [qw(sakila payment 17 49 )],
      [qw(sakila payment 18 0  )], # lower oob
      [qw(sakila payment 19 0  )], # upper oob
   ],
   "Checksum results through sakila.payment"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d sakila --resume),
      qw(--chunk-time 0)) },
);

$row = $master_dbh->selectall_arrayref('select db, tbl, chunk, master_cnt from percona.checksums order by db, tbl');
is_deeply(
   $row,
   [
      @$first_half,
      @$second_half,
   ],
   "Resume finished sakila"
);

(undef, $first_tbl) = split /\n/, $output;
like(
   $first_tbl,
   qr/sakila.rental$/,
   "Resumed from sakila.rental"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "Resumed 0 errors"
);

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   0,
   "Resumed 0 diffs"
);

is(
   PerconaTest::count_checksum_results($output, 'skipped'),
   0,
   "Resumed 0 skipped"
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   16_048,
   "Resumed 16,048 rows"
);

# ############################################################################
# Resume when master_crc wasn't updated.
# ############################################################################
load_data_infile("sakila-done-1k-chunks", "ts='2011-10-15 13:00:57'");
$master_dbh->do("delete from percona.checksums where ts > '2011-10-15 13:00:50'");
$master_dbh->do("update percona.checksums set master_crc=NULL, master_cnt=NULL, ts='2011-11-11 11:11:11' where db='sakila' and tbl='rental' and chunk=12");

# Checksum table now ends with:
#    *************************** 49. row ***************************
#    db: sakila
#    tbl: rental
#    chunk: 11
#    chunk_time: 0.006462
#    chunk_index: PRIMARY
#    lower_boundary: 10005
#    upper_boundary: 11004
#    this_crc: d2ad38b8
#    this_cnt: 1000
#    master_crc: d2ad38b8
#    master_cnt: 1000
#    ts: 2011-10-15 13:00:49
#    *************************** 50. row ***************************
#    db: sakila
#    tbl: rental
#    chunk: 12
#    chunk_time: 0.00984
#    chunk_index: PRIMARY
#    lower_boundary: 11005
#    upper_boundary: 12004
#    this_crc: 3b07b7a1
#    this_cnt: 1000
#    master_crc: NULL
#    master_cnt: NULL
#    ts: 2011-11-07 10:45:20
# This ^ last row is bad because master_crc and master_cnt are NULL,
# which means the tool was killed before $update_sth was called.  So,
# it should resume from chunk 11 of this table and overwrite chunk 12.

my $chunk11 = $master_dbh->selectall_arrayref(q{select * from percona.checksums where db='sakila' and tbl='rental' and chunk=11});

my $chunk12 = $master_dbh->selectall_arrayref(q{select master_crc from percona.checksums where db='sakila' and tbl='rental' and chunk=12});
is(
   $chunk12->[0]->[0],
   undef,
   "Chunk 12 master_crc is null"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d sakila --resume),
      qw(--chunk-time 0)) },
   trf => sub { return PerconaTest::normalize_checksum_results(@_) },
);

$row = $master_dbh->selectall_arrayref('select db, tbl, chunk, master_cnt from percona.checksums order by db, tbl');
is_deeply(
   $row,
   [
      @$first_half,
      @$second_half,
   ],
   "Resume finished sakila"
);

is(
   $output,
"Resuming from sakila.rental chunk 11, timestamp 2011-10-15 13:00:49
ERRORS DIFFS ROWS CHUNKS SKIPPED TABLE
0 0 5044 8 0 sakila.rental
0 0 2 1 0 sakila.staff
0 0 2 1 0 sakila.store
",
   "Resumed from last updated chunk"
);

is_deeply(
   $master_dbh->selectall_arrayref(q{select * from percona.checksums where db='sakila' and tbl='rental' and chunk=11}),
   $chunk11,
   "Chunk 11 not updated"
);

$chunk12 = $master_dbh->selectall_arrayref(q{select master_crc, master_cnt from percona.checksums where db='sakila' and tbl='rental' and chunk=12});
ok(
   defined $chunk12->[0]->[0],
   "Chunk 12 master_crc updated"
);

# ############################################################################
# Resume with --ignore-table.
# ############################################################################
$sb->load_file('master', "t/pt-table-checksum/samples/3tbl-resume.sql");
load_data_infile("3tbl-resume", "ts='2011-11-08 00:00:24'");

$master_dbh->do("delete from percona.checksums where ts > '2011-11-08 00:00:11'");
my $before = $master_dbh->selectall_arrayref("select db, tbl, chunk, ts from percona.checksums where tbl='t1' or tbl='t2' order by db, tbl");
is_deeply(
   $before,
   [
      [qw( test t1  1 ), '2011-11-08 00:00:01'],
      [qw( test t1  2 ), '2011-11-08 00:00:02'],
      [qw( test t1  3 ), '2011-11-08 00:00:03'],
      [qw( test t1  4 ), '2011-11-08 00:00:04'],
      [qw( test t1  5 ), '2011-11-08 00:00:05'],
      [qw( test t1  6 ), '2011-11-08 00:00:06'],
      [qw( test t1  7 ), '2011-11-08 00:00:07'], # lower oob
      [qw( test t1  8 ), '2011-11-08 00:00:08'], # upper oob
      [qw( test t2  1 ), '2011-11-08 00:00:09'],
      [qw( test t2  2 ), '2011-11-08 00:00:10'],
      [qw( test t2  3 ), '2011-11-08 00:00:11'],
   ],
   "Checksum results through t2 chunk 3"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d test --resume),
      qw(--ignore-tables test.t2 --chunk-size 5 --chunk-time 0)) },
   trf => sub { return PerconaTest::normalize_checksum_results(@_) },
);

is(
   $output,
"ERRORS DIFFS ROWS CHUNKS SKIPPED TABLE
0 0 26 8 0 test.t3
",
   "Resumed from t3"
);

$row = $master_dbh->selectall_arrayref('select db, tbl, chunk from percona.checksums order by db, tbl');
is_deeply(
   $row,
   [
      [qw( test t1  1 )], 
      [qw( test t1  2 )],
      [qw( test t1  3 )],
      [qw( test t1  4 )],
      [qw( test t1  5 )],
      [qw( test t1  6 )],
      [qw( test t1  7 )],
      [qw( test t1  8 )],
      [qw( test t2  1 )],
      [qw( test t2  2 )],
      [qw( test t2  3 )],
      # t2 not resumed
      [qw( test t3  1 )],
      [qw( test t3  2 )],
      [qw( test t3  3 )],
      [qw( test t3  4 )],
      [qw( test t3  5 )],
      [qw( test t3  6 )],
      [qw( test t3  7 )],
      [qw( test t3  8 )],
   ],
   "--resume and --ignore-table"
);

is_deeply(
   $master_dbh->selectall_arrayref("select db, tbl, chunk, ts from percona.checksums where tbl='t1' or tbl='t2' order by db, tbl"),
   $before,
   "t1 and t2 checksums not updated"
);

# ############################################################################
# Resume from table that finished bounded chunks but not the 2 oob chunks.
# ############################################################################
$sb->load_file('master', "t/pt-table-checksum/samples/3tbl-resume.sql");
load_data_infile("3tbl-resume", "ts='2011-11-08 00:00:24'");

# This will truncate the checksum results after t1 chunk 6 where chunk 7
# is the lower oob and chunk 8 is the upper oob.
$master_dbh->do("delete from percona.checksums where ts > '2011-11-08 00:00:06'");

is_deeply(
   $master_dbh->selectall_arrayref("select db, tbl, chunk, ts from percona.checksums order by db, tbl"),
   [
      [qw(test t1 1), '2011-11-08 00:00:01'],
      [qw(test t1 2), '2011-11-08 00:00:02'],
      [qw(test t1 3), '2011-11-08 00:00:03'],
      [qw(test t1 4), '2011-11-08 00:00:04'],
      [qw(test t1 5), '2011-11-08 00:00:05'],
      [qw(test t1 6), '2011-11-08 00:00:06'],
   ],
   "Checksum results through bounded t1 chunks"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d test --resume),
      qw(--chunk-size 5)) },
);

(undef, undef, $first_tbl) = split /\n/, $output;
like(
   $first_tbl,
   qr/test.t1$/,
   "Resumed from test.t1"
);

like(
   $output,
   qr/Resuming from test.t1 chunk 6, timestamp 2011-11-08 00:00:06/,
   "Resumed from test.t1 chunk 6"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "Resumed 0 errors"
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   52,
   "Resumed 52 rows"
);

is(
   PerconaTest::count_checksum_results($output, 'chunks'),
   18,
   "Resumed 18 chunks"
);

# ############################################################################
# Resume from table that finished bounded chunks and the lower oob chunk
# but not the upper oob chunk.
# ############################################################################
$sb->load_file('master', "t/pt-table-checksum/samples/3tbl-resume.sql");
load_data_infile("3tbl-resume", "ts='2011-11-08 00:00:24'");
$master_dbh->do("delete from percona.checksums where ts > '2011-11-08 00:00:07'");

is_deeply(
   $master_dbh->selectall_arrayref("select db, tbl, chunk, ts from percona.checksums order by db, tbl"),
   [
      [qw(test t1 1), '2011-11-08 00:00:01'],
      [qw(test t1 2), '2011-11-08 00:00:02'],
      [qw(test t1 3), '2011-11-08 00:00:03'],
      [qw(test t1 4), '2011-11-08 00:00:04'],
      [qw(test t1 5), '2011-11-08 00:00:05'],
      [qw(test t1 6), '2011-11-08 00:00:06'],
      [qw(test t1 7), '2011-11-08 00:00:07'], # lower oob
   ],
   "Checksum results through t1 lower oob chunk"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d test --resume),
      qw(--chunk-size 5)) },
);

(undef, undef, $first_tbl) = split /\n/, $output;
like(
   $first_tbl,
   qr/test.t1$/,
   "Resumed from test.t1"
);

like(
   $output,
   qr/Resuming from test.t1 chunk 7, timestamp 2011-11-08 00:00:07/,
   "Resumed from test.t1 chunk 7"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "Resumed 0 errors"
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   52,
   "Resumed 52 rows"
);

is(
   PerconaTest::count_checksum_results($output, 'chunks'),
   17,
   "Resumed 17 chunks"
);

# ###########################################################################
# Resume from earlier table when latter tables are complete.
# ###########################################################################

# See https://bugs.launchpad.net/percona-toolkit/+bug/898318

$sb->load_file('master', "t/pt-table-checksum/samples/3tbl-resume.sql");
load_data_infile("3tbl-resume-bar", "ts='2011-11-08 00:01:08'");

is_deeply(
   $master_dbh->selectall_arrayref("select db, tbl, chunk, ts from percona.checksums order by db, tbl"),
   [
      [qw(test	t1	1), '2011-11-08 00:02:01'],
      [qw(test	t1	2), '2011-11-08 00:02:02'],
      [qw(test	t1	3), '2011-11-08 00:02:03'],
      # t1 not finish but

      [qw(test	t2	1), '2011-11-08 00:01:01'],
      [qw(test	t2	2), '2011-11-08 00:01:02'],
      [qw(test	t2	3), '2011-11-08 00:01:03'],
      [qw(test	t2	4), '2011-11-08 00:01:04'],
      [qw(test	t2	5), '2011-11-08 00:01:05'],
      [qw(test	t2	6), '2011-11-08 00:01:06'],
      [qw(test	t2	7), '2011-11-08 00:01:07'],
      [qw(test	t2	8), '2011-11-08 00:01:08'],
      # t2 is finished
   ],
   "Checksum results partial t1, full t2"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d test --resume --tables t1),
      qw(--chunk-size 5)) },
);

like(
   $output,
   qr/Resuming from test.t1 chunk 3, timestamp 2011-11-08 00:02:03/,
   "Resume from t1 when t2 is done"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
