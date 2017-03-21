#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 15;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use PerconaTest;
use Quoter;
use TableParser;
use FileIterator;
use SchemaIterator;
use Schema;
use OptionParser;
use DSNParser;

my $in = "$trunk/t/lib/samples/mysqldump-no-data/";

my $q  = new Quoter;
my $tp = new TableParser(Quoter => $q);
my $fi = new FileIterator();

my $o  = new OptionParser(description => 'SchemaIterator');
@ARGV = qw();
$o->get_specs("$trunk/bin/pt-table-checksum");
$o->get_opts();

my $file_itr = $fi->get_file_itr("$in/dump001.txt");
my $sq       = new Schema();
my $si       = new SchemaIterator (
   file_itr     => $file_itr,
   OptionParser => $o,
   Quoter       => $q,
   TableParser  => $tp,
   Schema       => $sq,
);

# Init the schema (SchemaIterator calls Schema::add_schema_object()).
1 while(defined $si->next());

#ok(
#   $sq->is_duplicate_column('c1')
#   && $sq->is_duplicate_column('c2'),
#   "Duplicate columns in dump001.txt"
#);

#ok(
#   $sq->is_duplicate_table('a'),
#   "Duplicate tables in dump001.txt"
#);


# ############################################################################
# Test find columns in the schema.
# ############################################################################

sub test_find_col {
   my ($got, $expect, $test_name) = @_;

   my @got_tbls;
   foreach my $tbl ( @$got ) {
      push @got_tbls, [$tbl->{db}, $tbl->{tbl}];
   }

   is_deeply(
      \@got_tbls,
      $expect,
      $test_name,
   ) or print Dumper(\@got_tbls);
}

# First by column name, what would be parsed from a query.

test_find_col(
   $sq->find_column(col_name => 'c3'),
   [['test','b']],
   "Find column c3"
);

test_find_col(
   $sq->find_column(col_name => 'b.c3'),
   [['test','b']],
   "Find column b.c3"
);

test_find_col(
   $sq->find_column(col_name => 'test.b.c3'),
   [['test','b']],
   "Find column test.b.c3"
);

test_find_col(
   $sq->find_column(col_name => 'c1'),
   [
      ['test',  'b'],
      ['test',  'a'],
      ['test2', 'a'],
   ],
   "Find duplicate column c1"
);

test_find_col(
   $sq->find_column(col_name => 'a.c1'),
   [
      ['test',  'a'],
      ['test2', 'a'],
   ],
   "Find duplicate table.column a.c1"
);

test_find_col(
   $sq->find_column(col_name => 'xyz'),
   [],
   "Cannot find nonexistent column name"
);

# Then by a tbl struct, what's used by Schema.

test_find_col(
   $sq->find_column(col => 'c3'),
   [['test','b']],
   "Find column c3 (struct)"
);

test_find_col(
   $sq->find_column(tbl => 'b', col => 'c3'),
   [['test','b']],
   "Find column b.c3 (struct)"
);

test_find_col(
   $sq->find_column(db => 'test', tbl => 'b', col => 'c3'),
   [['test','b']],
   "Find column test.b.c3 (struct)"
);

test_find_col(
   $sq->find_column(col => 'c1'),
   [
      ['test',  'b'],
      ['test',  'a'],
      ['test2', 'a'],
   ],
   "Find duplicate column c1 (struct)"
);

test_find_col(
   $sq->find_column(tbl => 'a', col => 'c1'),
   [
      ['test',  'a'],
      ['test2', 'a'],
   ],
   "Find duplicate table.column a.c1 (struct)"
);

test_find_col(
   $sq->find_column(col => 'xyz'),
   [],
   "Cannot find nonexistent column name (struct)"
);

# ############################################################################
# Test find tables in the schema.
# ############################################################################

sub test_find_tbl {
   my ($got, $expect, $test_name) = @_;

   my @got_dbs;
   foreach my $db ( @$got ) {
      push @got_dbs, $db;
   }

   is_deeply(
      \@got_dbs,
      $expect,
      $test_name,
   ) or print Dumper(\@got_dbs);
}

test_find_tbl(
   $sq->find_table(tbl => 'a'),
   ['test', 'test2'],
   "Find table a"
);

# ############################################################################
# Test ignore.
# ############################################################################
test_find_col(
   $sq->find_column(
      col    => 'c1',
      ignore => [
         { db => 'test',  tbl => 'a' },
         { db => 'test2', tbl => 'a' },
      ],
   ),
   [
      #['test',  'a'],  # IGNORED
      ['test',  'b'],
      #['test2', 'a'],  # IGNORED
   ],
   "Ignore tables"
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $sq->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
