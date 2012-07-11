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

use Data::Dumper;
$Data::Dumper::Indent    = 0;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $c1_dbh = $sb->get_dbh_for('master');

diag(`$trunk/sandbox/start-sandbox master 2900 >/dev/null`);
my $r1_dbh = $sb->get_dbh_for('master3');

diag(`$trunk/sandbox/start-sandbox master 2901 >/dev/null`);
my $r2_dbh = $sb->get_dbh_for('master4');

if ( !$c1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$r1_dbh ) {
   plan skip_all => 'Cannot connect to second sandbox master';

}
else {
   plan tests => 23;
}

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';
my @args = ('-F', $cnf, 'h=127.1,P=12345', 'P=2900', qw(-d bidi --bidirectional));

$sb->wipe_clean($c1_dbh);
$sb->wipe_clean($r1_dbh);

sub load_bidi_data {
   $sb->load_file('master', 't/pt-table-sync/samples/bidirectional/table.sql');
   $sb->load_file('master3', 't/pt-table-sync/samples/bidirectional/table.sql');
   $sb->load_file('master', 't/pt-table-sync/samples/bidirectional/master-data.sql');
   $sb->load_file('master3', 't/pt-table-sync/samples/bidirectional/remote-1.sql');
}

my $r1_data_synced =  [
   [1,   'abc',   1,  '2010-02-01 05:45:30'],
   [2,   'def',   2,  '2010-01-31 06:11:11'],
   [3,   'ghi',   5,  '2010-02-01 09:17:52'],
   [4,   'jkl',   6,  '2010-02-01 10:11:33'],
   [5,   undef,   0,  '2010-02-02 05:10:00'],
   [6,   'p',     4,  '2010-01-31 10:17:00'],
   [7,   'qrs',   5,  '2010-02-01 10:11:11'],
   [8,   'tuv',   6,  '2010-01-31 10:17:20'],
   [9,   'wxy',   7,  '2010-02-01 10:17:00'],
   [10,  'z',     8,  '2010-01-31 10:17:08'],
   [11,  '?',     0,  '2010-01-29 11:17:12'],
   [12,  '',      0,  '2010-02-01 11:17:00'],
   [13,  'hmm',   1,  '2010-02-02 12:17:31'],
   [14,  undef,   0,  '2010-01-31 10:17:00'],
   [15,  'gtg',   7,  '2010-02-02 06:01:08'],
   [17,  'good',  1,  '2010-02-02 21:38:03'],
   [20,  'new', 100,  '2010-02-01 04:15:36'],
];


load_bidi_data();
$c1_dbh->do('use bidi');
$r1_dbh->do('use bidi');

my $res = $c1_dbh->selectall_arrayref('select * from bidi.t order by id');
is_deeply(
   $res,
   [
      [1,   'abc',   1,  '2010-02-01 05:45:30'],
      [2,   'def',   2,  '2010-01-31 06:11:11'],
      [3,   'ghi',   5,  '2010-02-01 09:17:52'],
      [4,   'jkl',   6,  '2010-02-01 10:11:33'],
      [5,   'mno',   3,  '2010-02-01 10:17:40'],
      [6,   'p',     4,  '2010-01-31 10:17:00'],
      [7,   'qrs',   5,  '2010-02-01 10:11:11'],
      [8,   'tuv',   6,  '2010-01-31 10:17:20'],
      [9,   'wxy',   7,  '2010-02-01 10:17:00'],
      [10,  'z',     8,  '2010-01-31 10:17:08'],
      [12,  '',      0,  '2010-02-01 11:17:00'],
      [13,  undef,   0,  '2010-02-01 12:17:31'],
      [14,  undef,   0,  '2010-01-31 10:17:00'],
      [15,  'NA',    0,  '2010-01-31 07:00:01'],
      [20,  'new', 100,  '2010-02-01 04:15:36'],
   ],
   'c1 data before sync'
);

$res = $r1_dbh->selectall_arrayref('select * from bidi.t order by id');
is_deeply(
   $res,
   [
      [1,   'abc',   1,  '2010-02-01 05:45:30'],
      [2,   'def',   2,  '2010-01-31 06:11:11'],
      [3,   'ghi',   5,  '2010-02-01 09:17:51'],
      [4,   'jkl',   6,  '2010-02-01 10:11:33'],
      [5,   undef,   0,  '2010-02-02 05:10:00'],
      [6,   'p',     4,  '2010-01-31 10:17:00'],
      [7,   'qrs',   5,  '2010-02-01 10:11:11'],
      [8,   'tuv',   6,  '2010-01-31 10:17:20'],
      [9,   'wxy',   7,  '2010-02-01 10:17:00'],
      [10,  'z',     8,  '2010-01-31 10:17:08'],
      [11,  '?',     0,  '2010-01-29 11:17:12'],
      [12,  '',      0,  '2010-02-01 11:17:00'],
      [13,  'hmm',   1,  '2010-02-02 12:17:31'],
      [14,  undef,   0,  '2010-01-31 10:17:00'],
      [15,  'gtg',   7,  '2010-02-02 06:01:08'],
      [17,  'good',  1,  '2010-02-02 21:38:03'],
   ],
   'r1 data before sync'
);

$output = output(
   sub { pt_table_sync::main(@args, qw(--print --execute),
      qw(--conflict-column ts --conflict-comparison newest)) }
);

is(
   $output,
"/*127.1:2900*/ UPDATE `bidi`.`t` SET `c`='ghi', `d`='5', `ts`='2010-02-01 09:17:52' WHERE `id`='3' LIMIT 1;
/*127.1:12345*/ UPDATE `bidi`.`t` SET `c`=NULL, `d`='0', `ts`='2010-02-02 05:10:00' WHERE `id`='5' LIMIT 1;
/*127.1:12345*/ INSERT INTO `bidi`.`t`(`id`, `c`, `d`, `ts`) VALUES ('11', '?', '0', '2010-01-29 11:17:12');
/*127.1:12345*/ UPDATE `bidi`.`t` SET `c`='hmm', `d`='1', `ts`='2010-02-02 12:17:31' WHERE `id`='13' LIMIT 1;
/*127.1:12345*/ UPDATE `bidi`.`t` SET `c`='gtg', `d`='7', `ts`='2010-02-02 06:01:08' WHERE `id`='15' LIMIT 1;
/*127.1:12345*/ INSERT INTO `bidi`.`t`(`id`, `c`, `d`, `ts`) VALUES ('17', 'good', '1', '2010-02-02 21:38:03');
/*127.1:2900*/ INSERT INTO `bidi`.`t`(`id`, `c`, `d`, `ts`) VALUES ('20', 'new', '100', '2010-02-01 04:15:36');
",
   '--print correct SQL for c1<->r1 bidirectional sync'
);

$res = $c1_dbh->selectall_arrayref('select * from bidi.t order by id');
is_deeply(
   $res,
   $r1_data_synced,
   'Synced c1'
);

$res = $r1_dbh->selectall_arrayref('select * from bidi.t order by id');
is_deeply(
   $res,
   $r1_data_synced,
   'Synced r1'
);

# Set a threshold which will cause some unresolvable conflicts.
load_bidi_data();

my $err = '';
{
   local *STDERR;
   open STDERR, '>', \$err;
   $output = output(
      sub { pt_table_sync::main(@args, qw(--print --execute),
         qw(--conflict-column ts --conflict-comparison newest),
         qw(--conflict-threshold 30m)) }
   );
}

is(
   $output,
"/*127.1:12345*/ UPDATE `bidi`.`t` SET `c`=NULL, `d`='0', `ts`='2010-02-02 05:10:00' WHERE `id`='5' LIMIT 1;
/*127.1:12345*/ INSERT INTO `bidi`.`t`(`id`, `c`, `d`, `ts`) VALUES ('11', '?', '0', '2010-01-29 11:17:12');
/*127.1:12345*/ UPDATE `bidi`.`t` SET `c`='hmm', `d`='1', `ts`='2010-02-02 12:17:31' WHERE `id`='13' LIMIT 1;
/*127.1:12345*/ UPDATE `bidi`.`t` SET `c`='gtg', `d`='7', `ts`='2010-02-02 06:01:08' WHERE `id`='15' LIMIT 1;
/*127.1:12345*/ INSERT INTO `bidi`.`t`(`id`, `c`, `d`, `ts`) VALUES ('17', 'good', '1', '2010-02-02 21:38:03');
/*127.1:2900*/ INSERT INTO `bidi`.`t`(`id`, `c`, `d`, `ts`) VALUES ('20', 'new', '100', '2010-02-01 04:15:36');
",
  'SQL for c1<->r1 with conflict'
);

is(
   $err,
"# Cannot resolve conflict WHERE `id`='3': `ts` values do not differ by the threhold, 30m.
",
   'Warns about conflict'
);

$res = $c1_dbh->selectall_arrayref('select * from bidi.t order by id');
is_deeply(
   $res,
   [
      [1,   'abc',   1,  '2010-02-01 05:45:30'],
      [2,   'def',   2,  '2010-01-31 06:11:11'],
      [3,   'ghi',   5,  '2010-02-01 09:17:52'], # not synced
      [4,   'jkl',   6,  '2010-02-01 10:11:33'],
      [5,   undef,   0,  '2010-02-02 05:10:00'],
      [6,   'p',     4,  '2010-01-31 10:17:00'],
      [7,   'qrs',   5,  '2010-02-01 10:11:11'],
      [8,   'tuv',   6,  '2010-01-31 10:17:20'],
      [9,   'wxy',   7,  '2010-02-01 10:17:00'],
      [10,  'z',     8,  '2010-01-31 10:17:08'],
      [11,  '?',     0,  '2010-01-29 11:17:12'],
      [12,  '',      0,  '2010-02-01 11:17:00'],
      [13,  'hmm',   1,  '2010-02-02 12:17:31'],
      [14,  undef,   0,  '2010-01-31 10:17:00'],
      [15,  'gtg',   7,  '2010-02-02 06:01:08'],
      [17,  'good',  1,  '2010-02-02 21:38:03'],
      [20,  'new', 100,  '2010-02-01 04:15:36'],
   ],
   'Synced c1 except conflict'
);

$res = $r1_dbh->selectall_arrayref('select * from bidi.t order by id');
is_deeply(
   $res,
   [
      [1,   'abc',   1,  '2010-02-01 05:45:30'],
      [2,   'def',   2,  '2010-01-31 06:11:11'],
      [3,   'ghi',   5,  '2010-02-01 09:17:51'], # not synced
      [4,   'jkl',   6,  '2010-02-01 10:11:33'],
      [5,   undef,   0,  '2010-02-02 05:10:00'],
      [6,   'p',     4,  '2010-01-31 10:17:00'],
      [7,   'qrs',   5,  '2010-02-01 10:11:11'],
      [8,   'tuv',   6,  '2010-01-31 10:17:20'],
      [9,   'wxy',   7,  '2010-02-01 10:17:00'],
      [10,  'z',     8,  '2010-01-31 10:17:08'],
      [11,  '?',     0,  '2010-01-29 11:17:12'],
      [12,  '',      0,  '2010-02-01 11:17:00'],
      [13,  'hmm',   1,  '2010-02-02 12:17:31'],
      [14,  undef,   0,  '2010-01-31 10:17:00'],
      [15,  'gtg',   7,  '2010-02-02 06:01:08'],
      [17,  'good',  1,  '2010-02-02 21:38:03'],
      [20,  'new', 100,  '2010-02-01 04:15:36'],
   ],
   'Synced r1 except conflict'
);

# Now die on conflict error.
load_bidi_data();

{
   $err = '';
   local *STDERR;
   open STDERR, '>', \$err;
   $output = output(
      sub { pt_table_sync::main(@args, qw(--print --execute),
         qw(--conflict-column ts --conflict-comparison newest),
         qw(--conflict-threshold 30m --conflict-error die)) }
   );
};

is(
   $output,
   "",
  'No SQL for c1<->r1 with die on conflict'
);

# mk-table-sync catches death and warns instead so it can continue
# syncing other tables.
is(
   $err,
"# Cannot resolve conflict WHERE `id`='3': `ts` values do not differ by the threhold, 30m.  while doing bidi.t on 127.1
",
   'Die/warn about conflict'
);

$res = $c1_dbh->selectall_arrayref('select * from bidi.t order by id');
is_deeply(
   $res,
   [
      [1,   'abc',   1,  '2010-02-01 05:45:30'],
      [2,   'def',   2,  '2010-01-31 06:11:11'],
      [3,   'ghi',   5,  '2010-02-01 09:17:52'],
      [4,   'jkl',   6,  '2010-02-01 10:11:33'],
      [5,   'mno',   3,  '2010-02-01 10:17:40'],
      [6,   'p',     4,  '2010-01-31 10:17:00'],
      [7,   'qrs',   5,  '2010-02-01 10:11:11'],
      [8,   'tuv',   6,  '2010-01-31 10:17:20'],
      [9,   'wxy',   7,  '2010-02-01 10:17:00'],
      [10,  'z',     8,  '2010-01-31 10:17:08'],
      [12,  '',      0,  '2010-02-01 11:17:00'],
      [13,  undef,   0,  '2010-02-01 12:17:31'],
      [14,  undef,   0,  '2010-01-31 10:17:00'],
      [15,  'NA',    0,  '2010-01-31 07:00:01'],
      [20,  'new', 100,  '2010-02-01 04:15:36'],
   ],
   'c1 not synced due to die on conflict'
);

$res = $r1_dbh->selectall_arrayref('select * from bidi.t order by id');
is_deeply(
   $res,
   [
      [1,   'abc',   1,  '2010-02-01 05:45:30'],
      [2,   'def',   2,  '2010-01-31 06:11:11'],
      [3,   'ghi',   5,  '2010-02-01 09:17:51'],
      [4,   'jkl',   6,  '2010-02-01 10:11:33'],
      [5,   undef,   0,  '2010-02-02 05:10:00'],
      [6,   'p',     4,  '2010-01-31 10:17:00'],
      [7,   'qrs',   5,  '2010-02-01 10:11:11'],
      [8,   'tuv',   6,  '2010-01-31 10:17:20'],
      [9,   'wxy',   7,  '2010-02-01 10:17:00'],
      [10,  'z',     8,  '2010-01-31 10:17:08'],
      [11,  '?',     0,  '2010-01-29 11:17:12'],
      [12,  '',      0,  '2010-02-01 11:17:00'],
      [13,  'hmm',   1,  '2010-02-02 12:17:31'],
      [14,  undef,   0,  '2010-01-31 10:17:00'],
      [15,  'gtg',   7,  '2010-02-02 06:01:08'],
      [17,  'good',  1,  '2010-02-02 21:38:03'],
   ],
   'r1 not synced due to die on conflict'
);


# #############################################################################
# Test bidirectional sync with 3 servers.
# #############################################################################

# It's confusing but master4 = 2901, aka our 3rd master server.

SKIP: {
   skip 'Cannot connect to third sandbox master', 9 unless $r2_dbh;

   load_bidi_data();
   $sb->load_file('master4', 't/pt-table-sync/samples/bidirectional/table.sql');
   $sb->load_file('master4', 't/pt-table-sync/samples/bidirectional/remote-2.sql');

   $res = $r2_dbh->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      [
         [1,   'abc',   1,  '2010-02-01 05:45:30'],
         [3,   'ghi',   5,  '2010-02-01 09:17:52'], 
         [4,   'jkl',   6,  '2010-02-01 10:11:33'],
         [5,   'mno',   3,  '2010-02-01 10:17:40'],
         [6,   'p',     4,  '2010-01-31 10:17:00'],
         [7,   'qrs',   5,  '2010-02-01 10:11:11'],
         [8,   'TUV',   6,  '2010-01-31 10:17:20'],
         [9,   'wxy',   7,  '2010-02-01 10:17:00'],
         [10,  'rdy',   5,  '2010-02-02 09:09:10'],
         [11,  '?',     0,  '2010-01-29 12:19:48'],
         [12,  '',      0,  '2010-02-01 13:17:19'],
         [13,  undef,   0,  '2010-02-01 12:17:31'],
         [14,  undef,   0,  '2010-02-02 13:00:00'],
         [15,  'NA',    0,  '2010-01-31 07:00:01'],
         [16,  undef,   0,  '2010-02-02 13:20:00'],
      ],
      'r2 data before sync'
   );

   {
      $err = '';
      local *STDERR;
      open STDERR, '>', \$err;
      $output = output(
         sub { pt_table_sync::main(@args, 'h=127.1,P=2901',
            qw(--print --execute --chunk-size 2),
            qw(--conflict-column ts --conflict-comparison newest)) }
      );
   }

   like(
      $err,
      qr/Cannot resolve conflict WHERE `id`='8': `ts` values are the same/,
      'Warned that id=8 differs but has same ts'
   );

   $res = $c1_dbh->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      [
         ['1','abc','1','2010-02-01 05:45:30'],
         ['2','def','2','2010-01-31 06:11:11'],
         ['3','ghi','5','2010-02-01 09:17:52'],
         ['4','jkl','6','2010-02-01 10:11:33'],
         ['5',undef,'0','2010-02-02 05:10:00'],
         ['6','p','4','2010-01-31 10:17:00'],
         ['7','qrs','5','2010-02-01 10:11:11'],
         ['8','tuv','6','2010-01-31 10:17:20'],
         ['9','wxy','7','2010-02-01 10:17:00'],
         ['10','rdy','5','2010-02-02 09:09:10'],
         ['11','?','0','2010-01-29 12:19:48'],
         ['12','','0','2010-02-01 13:17:19'],
         ['13','hmm','1','2010-02-02 12:17:31'],
         ['14',undef,'0','2010-02-02 13:00:00'],
         ['15','gtg','7','2010-02-02 06:01:08'],
         ['16',undef,'0','2010-02-02 13:20:00'],
         ['17','good','1','2010-02-02 21:38:03'],
         ['20','new','100','2010-02-01 04:15:36']
      ],
      'c1 data synced 1st pass'
   );

   $res = $r1_dbh->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      [
         ['1','abc','1','2010-02-01 05:45:30'],
         ['2','def','2','2010-01-31 06:11:11'],
         ['3','ghi','5','2010-02-01 09:17:52'],
         ['4','jkl','6','2010-02-01 10:11:33'],
         ['5',undef,'0','2010-02-02 05:10:00'],
         ['6','p','4','2010-01-31 10:17:00'],
         ['7','qrs','5','2010-02-01 10:11:11'],
         ['8','tuv','6','2010-01-31 10:17:20'],
         ['9','wxy','7','2010-02-01 10:17:00'],
         ['10','z','8','2010-01-31 10:17:08'],
         ['11','?','0','2010-01-29 11:17:12'],
         ['12','','0','2010-02-01 11:17:00'],
         ['13','hmm','1','2010-02-02 12:17:31'],
         ['14',undef,'0','2010-01-31 10:17:00'],
         ['15','gtg','7','2010-02-02 06:01:08'],
         ['17','good','1','2010-02-02 21:38:03'],
         ['20','new','100','2010-02-01 04:15:36']
      ],
      'r1 data synced 1st pass'
   );

   $res = $r2_dbh->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      [
         ['1','abc','1','2010-02-01 05:45:30'],
         ['2','def','2','2010-01-31 06:11:11'],
         ['3','ghi','5','2010-02-01 09:17:52'],
         ['4','jkl','6','2010-02-01 10:11:33'],
         ['5',undef,'0','2010-02-02 05:10:00'],
         ['6','p','4','2010-01-31 10:17:00'],
         ['7','qrs','5','2010-02-01 10:11:11'],
         ['8','TUV','6','2010-01-31 10:17:20'],
         ['9','wxy','7','2010-02-01 10:17:00'],
         ['10','rdy','5','2010-02-02 09:09:10'],
         ['11','?','0','2010-01-29 12:19:48'],
         ['12','','0','2010-02-01 13:17:19'],
         ['13','hmm','1','2010-02-02 12:17:31'],
         ['14',undef,'0','2010-02-02 13:00:00'],
         ['15','gtg','7','2010-02-02 06:01:08'],
         ['16',undef,'0','2010-02-02 13:20:00'],
         ['17','good','1','2010-02-02 21:38:03'],
         ['20','new','100','2010-02-01 04:15:36']
      ],
      'r2 data synced first pass'
   );

   # 2nd pass to sync r2 changes to r1
   {
      $err = '';
      local *STDERR;
      open STDERR, '>', \$err;
      $output = output(
         sub { pt_table_sync::main(@args, 'h=127.1,P=2901',
            qw(--print --execute --chunk-size 2),
            qw(--conflict-column ts --conflict-comparison newest)) }
      );
   }
   
   like(
      $err,
      qr/Cannot resolve conflict WHERE `id`='8': `ts` values are the same/,
      'Warned again that id=8 differs but has same ts'
   );

   my $all_synced = [
      ['1','abc','1','2010-02-01 05:45:30'],
      ['2','def','2','2010-01-31 06:11:11'],
      ['3','ghi','5','2010-02-01 09:17:52'],
      ['4','jkl','6','2010-02-01 10:11:33'],
      ['5',undef,'0','2010-02-02 05:10:00'],
      ['6','p','4','2010-01-31 10:17:00'],
      ['7','qrs','5','2010-02-01 10:11:11'],
      ['8','tuv','6','2010-01-31 10:17:20'],
      ['9','wxy','7','2010-02-01 10:17:00'],
      ['10','rdy','5','2010-02-02 09:09:10'],
      ['11','?','0','2010-01-29 12:19:48'],
      ['12','','0','2010-02-01 13:17:19'],
      ['13','hmm','1','2010-02-02 12:17:31'],
      ['14',undef,'0','2010-02-02 13:00:00'],
      ['15','gtg','7','2010-02-02 06:01:08'],
      ['16',undef,'0','2010-02-02 13:20:00'],
      ['17','good','1','2010-02-02 21:38:03'],
      ['20','new','100','2010-02-01 04:15:36']
   ];

   $res = $c1_dbh->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      $all_synced,
      'c1 data synced 2nd pass'
   );

   $res = $r1_dbh->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      $all_synced,
      'r1 data synced 2nd pass'
   );

   $res = $r2_dbh->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      [
         ['1','abc','1','2010-02-01 05:45:30'],
         ['2','def','2','2010-01-31 06:11:11'],
         ['3','ghi','5','2010-02-01 09:17:52'],
         ['4','jkl','6','2010-02-01 10:11:33'],
         ['5',undef,'0','2010-02-02 05:10:00'],
         ['6','p','4','2010-01-31 10:17:00'],
         ['7','qrs','5','2010-02-01 10:11:11'],
         # Identical to $all_synced except this conflicted row:
            ['8','TUV','6','2010-01-31 10:17:20'],
         ['9','wxy','7','2010-02-01 10:17:00'],
         ['10','rdy','5','2010-02-02 09:09:10'],
         ['11','?','0','2010-01-29 12:19:48'],
         ['12','','0','2010-02-01 13:17:19'],
         ['13','hmm','1','2010-02-02 12:17:31'],
         ['14',undef,'0','2010-02-02 13:00:00'],
         ['15','gtg','7','2010-02-02 06:01:08'],
         ['16',undef,'0','2010-02-02 13:20:00'],
         ['17','good','1','2010-02-02 21:38:03'],
         ['20','new','100','2010-02-01 04:15:36'],
      ],
      'r2 data synced 2nd pass'
   );
}

# #############################################################################
# Done.
# #############################################################################
diag(`$trunk/sandbox/stop-sandbox 2901 >/dev/null`);
diag(`$trunk/sandbox/stop-sandbox 2900 >/dev/null`);
$sb->wipe_clean($c1_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
