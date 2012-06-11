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

use PerconaTest;
use DSNParser;
use Sandbox;

use Cxn;
use Quoter;
use TableParser;
use OptionParser;
use IndexLength;

use constant PTDEBUG    => $ENV{PTDEBUG} || 0;
use constant PTDEVDEBUG => $ENV{PTDEBUG} || 0;

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
   plan tests => 7;
}

my $output;
my $q  = new Quoter();
my $tp = new TableParser(Quoter => $q);
my $il = new IndexLength(Quoter => $q);
my $o  = new OptionParser(description => 'IndexLength');
$o->get_specs("$trunk/bin/pt-table-checksum");
my $cxn = new Cxn(
   dbh          => $dbh,
   dsn          => { h=>'127.1', P=>'12345', n=>'h=127.1,P=12345' },
   DSNParser    => $dp,
   OptionParser => $o,
);

sub test_index_len {
   my (%args) = @_;
   my @required_args = qw(name tbl index len);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my ($len, $key) = $il->index_length(
      Cxn          => $cxn,
      tbl          => $args{tbl},
      index        => $args{index},
      n_index_cols => $args{n_index_cols},
   );

   is(
      $len,
      $args{len},
      "$args{name}"
   );
}

# #############################################################################
# bad_plan, PK with 4 cols
# #############################################################################
$sb->load_file('master', "t/pt-table-checksum/samples/bad-plan-bug-1010232.sql");
my $tbl_struct = $tp->parse(
   $tp->get_create_table($dbh, 'bad_plan', 't'));
my $tbl = {
   name       => $q->quote('bad_plan', 't'),
   tbl_struct => $tbl_struct,
};

for my $n ( 1..4 ) {
   my $len = $n * 2 + ($n >= 2  ? 1 : 0);
   test_index_len(
      name         => "bad_plan.t $n cols = $len bytes",
      tbl          => $tbl,
      index        => "PRIMARY",
      n_index_cols => $n,
      len          => $len,
   );
}

# #############################################################################
# Some sakila tables
# #############################################################################
$tbl_struct = $tp->parse(
   $tp->get_create_table($dbh, 'sakila', 'film_actor'));
$tbl = {
   name       => $q->quote('sakila', 'film_actor'),
   tbl_struct => $tbl_struct,
};

test_index_len(
   name         => "sakila.film_actor 1 col = 2 bytes",
   tbl          => $tbl,
   index        => "PRIMARY",
   n_index_cols => 1,
   len          => 2,
);

# #############################################################################
# Use full index if no n_index_cols
# #############################################################################

# Use sakila.film_actor stuff from previous tests.

test_index_len(
   name  => "sakila.film_actor all cols = 4 bytes",
   tbl   => $tbl,
   index => "PRIMARY",
   len   => 4,
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
