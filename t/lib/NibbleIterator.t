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
use MySQLDump;
use TableParser;
use TableNibbler;
use NibbleIterator;
use PerconaTest;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 6;
}


my $q  = new Quoter();
my $tp = new TableParser(Quoter=>$q);
my $du = new MySQLDump();
my $nb = new TableNibbler(TableParser=>$tp, Quoter=>$q);
my $o  = new OptionParser(description => 'NibbleIterator');

$o->get_specs("$trunk/bin/pt-table-checksum");

my %common_modules = (
   Quoter       => $q,
   TableParser  => $tp,
   MySQLDump    => $du,
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
      dbh          => $dbh,
      keep_ddl     => 1,
      Schema       => $schema,
      %common_modules,
   );
   1 while $si->next_schema_object();

   my $ni = new NibbleIterator(
      dbh => $dbh,
      tbl => $schema->get_table($args{db}, $args{tbl}),
      %common_modules,
   );

   return $ni;
}

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

# There's only 1 row left but extra calls shouldn't return anything or crash.
@rows = ();
for (1..5) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['z']],
   'a-z nibble 6'
) or print Dumper(\@rows);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
