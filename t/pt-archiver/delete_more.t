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
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
my $slave_dbh = $sb->get_dbh_for('slave1');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 19;
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
# Add path to samples to Perl's INC so the tool can find the module.
my $cmd = "perl -I $trunk/t/pt-archiver/samples $trunk/bin/pt-archiver";

# ###########################################################################
# Bulk delete with limit that results in 2 chunks.
# ###########################################################################
$sb->load_file('master', "t/pt-archiver/samples/delete_more.sql");
$dbh->do('use dm');

is_deeply(
   $dbh->selectall_arrayref('select * from `main_table-123` order by id'),
   [
      [1, '2010-02-16', 'a'],
      [2, '2010-02-15', 'b'],
      [3, '2010-02-15', 'c'],
      [4, '2010-02-16', 'd'],
      [5, '2010-02-14', 'e'],
   ],
   'main_table-123 data before archiving'
);

is_deeply(
   $dbh->selectall_arrayref('select * from `other_table-123` order by id'),
   [
      [1, 'a'],
      [2, 'b'],
      [2, 'b2'],
      [2, 'b3'],
      [3, 'c'],
      [4, 'd'],
      [5, 'e'],
      [6, 'ot1'],
   ],
   'other_table-123 data before archiving'
);

`$cmd --purge --primary-key-only --source F=$cnf,D=dm,t=main_table-123,i=pub_date,b=1,m=delete_more --where "pub_date < '2010-02-16'" --bulk-delete --limit 2`;

is_deeply(
   $dbh->selectall_arrayref('select * from `main_table-123` order by id'),
   [
      [1, '2010-02-16', 'a'],
      # [2, '2010-02-15', 'b'],
      # [3, '2010-02-15', 'c'],
      [4, '2010-02-16', 'd'],
      # [5, '2010-02-14', 'e'],
   ],
   'main_table-123 data after archiving (limit 2)'
);

is_deeply(
   $dbh->selectall_arrayref('select * from `other_table-123` order by id'),
   [
      [1, 'a'],
      [4, 'd'],
      [6, 'ot1'],
   ],
   'other_table-123 data after archiving (limit 2)'
);

SKIP: {
   skip 'Cannot connect to slave sandbox', 6 unless $slave_dbh;
   $slave_dbh->do('use dm');
   is_deeply(
      $slave_dbh->selectall_arrayref('select * from `main_table-123` order by id'),
      [
         [1, '2010-02-16', 'a'],
         [2, '2010-02-15', 'b'],
         [3, '2010-02-15', 'c'],
         [4, '2010-02-16', 'd'],
         [5, '2010-02-14', 'e'],
      ],
      'Slave main_table-123 not changed'
   );

   is_deeply(
      $slave_dbh->selectall_arrayref('select * from `other_table-123` order by id'),
      [
         [1, 'a'],
         [2, 'b'],
         [2, 'b2'],
         [2, 'b3'],
         [3, 'c'],
         [4, 'd'],
         [5, 'e'],
         [6, 'ot1'],
      ],
      'Slave other_table-123 not changed'
   );

   # Run it again without DSN b so changes should be made on slave.
   $sb->load_file('master', "t/pt-archiver/samples/delete_more.sql");

   is_deeply(
      $slave_dbh->selectall_arrayref('select * from `main_table-123` order by id'),
      [
         [1, '2010-02-16', 'a'],
         [2, '2010-02-15', 'b'],
         [3, '2010-02-15', 'c'],
         [4, '2010-02-16', 'd'],
         [5, '2010-02-14', 'e'],
      ],
      'Reset slave main_table-123'
   );

   is_deeply(
      $slave_dbh->selectall_arrayref('select * from `other_table-123` order by id'),
      [
         [1, 'a'],
         [2, 'b'],
         [2, 'b2'],
         [2, 'b3'],
         [3, 'c'],
         [4, 'd'],
         [5, 'e'],
         [6, 'ot1'],
      ],
      'Reset slave other_table-123'
   );

   `$cmd --purge --primary-key-only --source F=$cnf,D=dm,t=main_table-123,i=pub_date,m=delete_more --where "pub_date < '2010-02-16'" --bulk-delete --limit 2`;
   sleep 1;

   is_deeply(
      $slave_dbh->selectall_arrayref('select * from `main_table-123` order by id'),
      [
         [1, '2010-02-16', 'a'],
         # [2, '2010-02-15', 'b'],
         # [3, '2010-02-15', 'c'],
         [4, '2010-02-16', 'd'],
         # [5, '2010-02-14', 'e'],
      ],
      'Slave main_table-123 changed'
   );

   is_deeply(
      $slave_dbh->selectall_arrayref('select * from `other_table-123` order by id'),
      [
         [1, 'a'],
         [4, 'd'],
         [6, 'ot1'],
      ],
      'Slave other_table-123 changed'
   );
}

# ###########################################################################
# Bulk delete in single chunk.
# ###########################################################################
$sb->load_file('master', "t/pt-archiver/samples/delete_more.sql");
$dbh->do('use dm');

is_deeply(
   $dbh->selectall_arrayref('select * from `main_table-123` order by id'),
   [
      [1, '2010-02-16', 'a'],
      [2, '2010-02-15', 'b'],
      [3, '2010-02-15', 'c'],
      [4, '2010-02-16', 'd'],
      [5, '2010-02-14', 'e'],
   ],
   'main_table-123 data before archiving'
);

is_deeply(
   $dbh->selectall_arrayref('select * from `other_table-123` order by id'),
   [
      [1, 'a'],
      [2, 'b'],
      [2, 'b2'],
      [2, 'b3'],
      [3, 'c'],
      [4, 'd'],
      [5, 'e'],
      [6, 'ot1'],
   ],
   'other_table-123 data before archiving'
);

`$cmd --purge --primary-key-only --source F=$cnf,D=dm,t=main_table-123,i=pub_date,b=1,m=delete_more --where "pub_date < '2010-02-16'" --bulk-delete --limit 100`;

is_deeply(
   $dbh->selectall_arrayref('select * from `main_table-123` order by id'),
   [
      [1, '2010-02-16', 'a'],
      # [2, '2010-02-15', 'b'],
      # [3, '2010-02-15', 'c'],
      [4, '2010-02-16', 'd'],
      # [5, '2010-02-14', 'e'],
   ],
   'main_table-123 data after archiving (limit 100)'
);

is_deeply(
   $dbh->selectall_arrayref('select * from `other_table-123` order by id'),
   [
      [1, 'a'],
      [4, 'd'],
      [6, 'ot1'],
   ],
   'other_table-123 data after archiving (limit 100)'
);

# ###########################################################################
# Single delete.
# ###########################################################################
$sb->load_file('master', "t/pt-archiver/samples/delete_more.sql");
$dbh->do('use dm');

is_deeply(
   $dbh->selectall_arrayref('select * from `main_table-123` order by id'),
   [
      [1, '2010-02-16', 'a'],
      [2, '2010-02-15', 'b'],
      [3, '2010-02-15', 'c'],
      [4, '2010-02-16', 'd'],
      [5, '2010-02-14', 'e'],
   ],
   'main_table-123 data before archiving'
);

is_deeply(
   $dbh->selectall_arrayref('select * from `other_table-123` order by id'),
   [
      [1, 'a'],
      [2, 'b'],
      [2, 'b2'],
      [2, 'b3'],
      [3, 'c'],
      [4, 'd'],
      [5, 'e'],
      [6, 'ot1'],
   ],
   'other_table-123 data before archiving'
);

`$cmd --purge --primary-key-only --source F=$cnf,D=dm,t=main_table-123,i=pub_date,b=1,m=delete_more --where "pub_date < '2010-02-16'"`;
`$cmd --purge --primary-key-only --source F=$cnf,D=dm,t=main_table-123,i=pub_date,b=1,m=delete_more --where "pub_date < '2010-02-16'"`;

is_deeply(
   $dbh->selectall_arrayref('select * from `main_table-123` order by id'),
   [
      [1, '2010-02-16', 'a'],
      # [2, '2010-02-15', 'b'],
      # [3, '2010-02-15', 'c'],
      [4, '2010-02-16', 'd'],
      # [5, '2010-02-14', 'e'],
   ],
   'main_table-123 data after archiving (single delete)'
);

is_deeply(
   $dbh->selectall_arrayref('select * from `other_table-123` order by id'),
   [
      [1, 'a'],
      [4, 'd'],
      [6, 'ot1'],
   ],
   'other_table-123 data after archiving (single delete)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
