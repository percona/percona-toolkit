#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use KeySize;
use TableParser;
use Quoter;
use DSNParser;
use Sandbox;
use PerconaTest;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}

my $q  = new Quoter();
my $tp = new TableParser(Quoter => $q);
my $ks = new KeySize(Quoter=>$q);

my $tbl;
my $struct;
my %key;
my ($size, $chosen_key); 

sub key_info {
   my ( $file, $db, $tbl, $key, $cols ) = @_;
   $sb->load_file('master', $file, $db);
   my $tbl_name = $q->quote($db, $tbl);
   my $struct   = $tp->parse( load_file($file) );
   return (
      name       => $key,
      cols       => $cols || $struct->{keys}->{$key}->{cols},
      tbl_name   => $tbl_name,
      tbl_struct => $struct,
      dbh        => $dbh,
   );
}

$sb->create_dbs($dbh, ['test']);

isa_ok($ks, 'KeySize');

# With an empty table, the WHERE is impossible, so MySQL should optimize
# away the query, and key_len and rows will be NULL in EXPLAIN.
%key = key_info('t/lib/samples/dupe_key.sql', 'test', 'dupe_key', 'a');
is(
   $ks->get_key_size(%key),
   undef,
   'Empty table, impossible where'
);

# Populate the table to make the WHERE possible.
$dbh->do('INSERT INTO test.dupe_key VALUE (1,2,3),(4,5,6),(7,8,9),(0,0,0)');
is_deeply(
   [$ks->get_key_size(%key)],
   [20, 'a'],
   'Single column int key'
);

$key{name} = 'a_2';
is_deeply(
   [$ks->get_key_size(%key)],
   [40, 'a_2'],
   'Two column int key'
);

$sb->load_file('master', 't/lib/samples/issue_331-parent.sql', 'test');
%key = key_info('t/lib/samples/issue_331.sql', 'test', 'issue_331_t2', 'fk_1', ['id']);
($size, $chosen_key) = $ks->get_key_size(%key);
is(
   $size,
   8,
   'Foreign key size'
);
is(
   $chosen_key,
   'PRIMARY',
   'PRIMARY key chosen for foreign key'
);

# #############################################################################
# Issue 364: Argument "9,8" isn't numeric in multiplication (*) at
# mk-duplicate-key-checker line 1894
# #############################################################################
$dbh->do('USE test');
$dbh->do('DROP TABLE IF EXISTS test.issue_364');
%key = key_info(
   't/lib/samples/issue_364.sql',
   'test',
   'issue_364',
   'BASE_KID_ID',
   [qw(BASE_KID_ID ID)]
);
$sb->load_file('master', 't/lib/samples/issue_364-data.sql', 'test');

# This issue had another issue: the key is ALL CAPS, but TableParser
# lowercases all identifies, so KeySize said the key didn't exist.
# This was the root problem.  Once KeySize saw the key it added a
# FORCE INDEX and the index_merge went away.  Later, we'll drop the
# real key and add one back over the same columns so that KeySize
# won't see its key but one will exist with which to do merge_index.
ok(
   $ks->_key_exists(%key),
   'Key exists (issue 364)'
);

my $output = `/tmp/12345/use -D test -e 'EXPLAIN SELECT BASE_KID_ID, ID FROM test.issue_364 WHERE BASE_KID_ID=1 OR ID=1'`;
like(
   $output,
   qr/index_merge/,
   'Query uses index_merge (issue 364)'
);


($size, $chosen_key) = $ks->get_key_size(%key);
is(
   $size,
   17 * 176,
   'Key size (issue 364)'
);
is(
   $chosen_key,
   'BASE_KID_ID',
   'Chosen key (issue 364)'
);
is(
   $ks->error(),
   '',
   'No error (issue 364)'
);
like(
   $ks->explain(),
   qr/^extra: Using where; Using index
id: 1
key: BASE_KID_ID
key_len: 17
possible_keys: BASE_KID_ID
ref: NULL
rows: 17[1-9]
select_type: SIMPLE
table: issue_364
type: index\Z/,
   'EXPLAIN plan (issue 364)'
);
is(
   $ks->query(),
   'EXPLAIN SELECT BASE_KID_ID, ID FROM `test`.`issue_364` FORCE INDEX (`BASE_KID_ID`) WHERE BASE_KID_ID=1 OR ID=1',
   'Query (issue 364)'
);

# KeySize doesn't actually check the table to see if the key exists.
# It trusts that tbl_struct->{keys} is accurate.  So if we delete the
# key here, we'll fool KeySize and simulate the original problem.
delete $key{tbl_struct}->{keys}->{'base_kid_id'};
($size, $chosen_key) = $ks->get_key_size(%key);
is(
   $size,
   undef,
   'Key size 0 (issue 364)'
);
is(
   $chosen_key,
   undef,
   'Chose multiple keys (issue 364)'
);
is(
   $ks->error(),
   'MySQL chose multiple keys: BASE_KID_ID,PRIMARY',
   'Error about multiple keys (issue 364)'
);
is(
   $ks->query(),
   'EXPLAIN SELECT BASE_KID_ID, ID FROM `test`.`issue_364` WHERE BASE_KID_ID=1 OR ID=1',
   'Query without FORCE INDEX (issue 364)'
);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1201443
# #############################################################################
$sb->load_file('master', "t/pt-duplicate-key-checker/samples/fk_chosen_index_bug_1201443.sql");

($size, $chosen_key) = $ks->get_key_size(
   name       => 'child_ibfk_2',
   cols       => [qw(parent_id)],
   tbl_name   => 'fk_chosen_index_bug_1201443.child',
   tbl_struct => {
        charset => 'latin1',
        clustered_key => undef,
        col_posn => {
          id => 0,
          parent_id => 1
        },
        cols => [
          'id',
          'parent_id'
        ],
        defs => {
          id => '  `id` int(11) NOT NULL AUTO_INCREMENT',
          parent_id => '  `parent_id` int(11) NOT NULL'
        },
        engine => 'InnoDB',
        is_autoinc => {
          id => 1,
          parent_id => 0
        },
        is_col => {
          id => 1,
          parent_id => 1
        },
        is_nullable => {},
        is_numeric => {
          id => 1,
          parent_id => 1
        },
        keys => {
          id => {
            col_prefixes => [
              undef
            ],
            colnames => '`id`',
            cols => [
              'id'
            ],
            ddl => 'KEY `id` (`id`),',
            is_col => {
              id => 1
            },
            is_nullable => 0,
            is_unique => 0,
            name => 'id',
            type => 'BTREE'
          },
          parent_id => {
            col_prefixes => [
              undef
            ],
            colnames => '`parent_id`',
            cols => [
              'parent_id'
            ],
            ddl => 'KEY `parent_id` (`parent_id`),',
            is_col => {
              parent_id => 1
            },
            is_nullable => 0,
            is_unique => 0,
            name => 'parent_id',
            type => 'BTREE'
          }
        },
        name => 'child',
        null_cols => [],
        numeric_cols => [
          'id',
          'parent_id'
        ],
        type_for => {
          id => 'int',
          parent_id => 'int'
        }
      },
   dbh => $dbh,
);

cmp_ok(
   $size,
   '>',
   15_000,  # estimages range from 15k to 30k
   "Bug 1201443: size"
);

is(
   $chosen_key,
   'parent_id',
   "Bug 1201443: chosen key"
);

# #############################################################################
# Done.
# #############################################################################
$output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $ks->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
