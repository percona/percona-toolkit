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

use Schema;
use SchemaIterator;
use Quoter;
use DSNParser;
use Sandbox;
use OptionParser;
use TableParser;
use TableNibbler;
use RowChecksum;
use NibbleIterator;
use OobNibbleIterator;
use Cxn;
use PerconaTest;

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
my $output;

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 17;
}

my $q   = new Quoter();
my $tp  = new TableParser(Quoter=>$q);
my $nb  = new TableNibbler(TableParser=>$tp, Quoter=>$q);
my $o   = new OptionParser(description => 'OobNibbleIterator');
my $rc  = new RowChecksum(OptionParser => $o, Quoter=>$q);

$o->get_specs("$trunk/bin/pt-table-checksum");

my $cxn = new Cxn(
   dbh          => $dbh,
   dsn          => { h=>'127.1', P=>'12345', n=>'h=127.1,P=12345' },
   DSNParser    => $dp,
   OptionParser => $o,
);

my %common_modules = (
   Quoter       => $q,
   TableParser  => $tp,
   TableNibbler => $nb,
   OptionParser => $o,
);
my $in = "/t/lib/samples/NibbleIterator/";

sub make_nibble_iter {
   my (%args) = @_;

   if (my $file = $args{sql_file}) {
      $sb->load_file('master', "$in/$file");
   }

   @ARGV = $args{argv} ? @{$args{argv}} : ();
   $o->get_opts();

   my $schema = new Schema();
   my $si     = new SchemaIterator(
      dbh             => $dbh,
      keep_ddl        => 1,
      keep_tbl_status => 1,
      Schema          => $schema,
      %common_modules,
   );
   1 while $si->next();

   my $ni = new OobNibbleIterator(
      Cxn         => $cxn,
      tbl         => $schema->get_table($args{db}, $args{tbl}),
      chunk_size  => $o->get('chunk-size'),
      chunk_index => $o->get('chunk-index'),
      callbacks   => $args{callbacks},
      select      => $args{select},
      one_nibble  => $args{one_nibble},
      %common_modules,
   );

   return $ni;
}

# ############################################################################
# a-z w/ chunk-size 5, z is final boundary and single value
# ############################################################################
my $ni = make_nibble_iter(
   sql_file => "a-z.sql",
   db       => 'test',
   tbl      => 't',
   argv     => [qw(--databases test --chunk-size 5)],
);

my @rows = ();
for (1..5) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['a'],['b'],['c'],['d'],['e']],
   'a-z nibble 1'
) or print Dumper(\@rows);

@rows = ();
for (1..5) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['f'],['g'],['h'],['i'],['j']],
   'a-z nibble 2'
) or print Dumper(\@rows);

@rows = ();
for (1..5) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['k'],['l'],['m'],['n'],['o']],
   'a-z nibble 3'
) or print Dumper(\@rows);

@rows = ();
for (1..5) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['p'],['q'],['r'],['s'],['t']],
   'a-z nibble 4'
) or print Dumper(\@rows);

@rows = ();
for (1..5) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['u'],['v'],['w'],['x'],['y']],
   'a-z nibble 5'
) or print Dumper(\@rows);

@rows = ();
for (1..5) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['z']],
   'a-z nibble 6'
) or print Dumper(\@rows);

is(
   $ni->nibble_number(),
   8,
   "8 nibbles"
);

ok(
   !$ni->more_boundaries(),
   "No more boundaries"
);

# ############################################################################
# Get lower and upper oob values.
# ############################################################################
$ni = make_nibble_iter(
   sql_file => "a-z.sql",
   db       => 'test',
   tbl      => 't',
   argv     => [qw(--databases test --chunk-size 8)],
);

$dbh->do("delete from test.t where c='a' or c='z'");

@rows = ();
for (1..8) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['b'],['c'],['d'],['e'],['f'],['g'],['h'],['i']],
   'a-z nibble 1 with oob'
) or print Dumper(\@rows);

@rows = ();
for (1..8) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['j'],['k'],['l'],['m'],['n'],['o'],['p'],['q']],
   'a-z nibble 2 with oob'
) or print Dumper(\@rows);

@rows = ();
for (1..8) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['r'],['s'],['t'],['u'],['v'],['w'],['x'],['y']],
   'a-z nibble 3 with oob'
) or print Dumper(\@rows);

# NibbleIterator is done (b-y), now insert a row on the low end (a),
# and one on the high end (z), past what NibbleIterator originally
# saw as the first and last boundaries.  OobNibbleIterator should kick
# in and see a and z.
$dbh->do("insert into test.t values ('a'), ('z')");

# OobNibbleIterator checks the low end first.
@rows = ();
push @rows, $ni->next();
is_deeply(
   \@rows,
   [['a']],
   'a-z nibble 4 lower oob'
) or print Dumper(\@rows);

# Then it checks the high end.
@rows = ();
push @rows, $ni->next();
is_deeply(
   \@rows,
   [['z']],
   'a-z nibble 4 upper oob'
) or print Dumper(\@rows);

ok(
   !$ni->more_boundaries(),
   "No more boundaries"
);

# #############################################################################
# Empty table
# https://bugs.launchpad.net/percona-toolkit/+bug/987393 
# #############################################################################
$sb->load_file('master', "t/pt-table-checksum/samples/empty-table-bug-987393.sql");

$ni = make_nibble_iter(
   db       => 'test',
   tbl      => 'test_empty',
   argv     => [qw(--databases test --chunk-size-limit 0)],
);

@rows = ();
for (1..5) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [],
   "Empty table"
);

# #############################################################################
# Done.
# #############################################################################
{
   local *STDERR;
   open STDERR, '>', \$output;
   $ni->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
