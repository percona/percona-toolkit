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

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $q   = new Quoter();
my $tp  = new TableParser(Quoter=>$q);
my $nb  = new TableNibbler(TableParser=>$tp, Quoter=>$q);
my $o   = new OptionParser(description => 'NibbleIterator');
my $rc  = new RowChecksum(OptionParser => $o, Quoter=>$q);
my $cxn = new Cxn(
   dbh          => $dbh,
   dsn          => { h=>'127.1', P=>'12345', n=>'h=127.1,P=12345' },
   DSNParser    => $dp,
   OptionParser => $o,
);

$o->get_specs("$trunk/bin/pt-table-checksum");

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

   my $ni = new NibbleIterator(
      Cxn         => $cxn,
      tbl         => $schema->get_table(lc($args{db}), lc($args{tbl})),
      chunk_size  => $o->get('chunk-size'),
      chunk_index => $o->get('chunk-index'),
      callbacks   => $args{callbacks},
      select      => $args{select},
      one_nibble  => $args{one_nibble},
      resume      => $args{resume},
      order_by    => $args{order_by},
      comments    => $args{comments},
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

ok(
   !$ni->one_nibble(),
   "one_nibble() false"
);

is(
   $ni->nibble_number(),
   0,
   "nibble_number() 0"
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

is(
   $ni->nibble_number(),
   1,
   "nibble_number() 1"
);

@rows = ();
for (1..5) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['f'],['g'],['h'],['i'],['j']],
   'a-z nibble 2'
) or print Dumper(\@rows);

is(
   $ni->nibble_number(),
   2,
   "nibble_number() 2"
);

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

ok(
   $ni->more_boundaries(),
   "more_boundaries() true"
);

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

ok(
   !$ni->more_boundaries(),
   "more_boundaries() false"
);

is(
   $ni->chunk_size(),
   5,
   "chunk_size()"
);

# ############################################################################
# a-y w/ chunk-size 5, even nibbles
# ############################################################################
$dbh->do("delete from test.t where c='z'");
my $all_rows = $dbh->selectall_arrayref('select * from test.t order by c');
$ni = make_nibble_iter(
   db       => 'test',
   tbl      => 't',
   argv     => [qw(--databases test --chunk-size 5)],
);

@rows = ();
for (1..26) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   $all_rows,
   'a-y even nibble'
) or print Dumper(\@rows);

# ############################################################################
# chunk-size exceeds number of rows, 1 nibble
# ############################################################################
$ni = make_nibble_iter(
   db       => 'test',
   tbl      => 't',
   argv     => [qw(--databases test --chunk-size 100)],
);

@rows = ();
for (1..27) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   $all_rows,
   '1 nibble'
) or diag(Dumper(\@rows));

# ############################################################################
# single row table
# ############################################################################
$dbh->do("delete from test.t where c != 'd'");
$ni = make_nibble_iter(
   db       => 'test',
   tbl      => 't',
   argv     => [qw(--databases test --chunk-size 100)],
);

ok(
   $ni->one_nibble(),
   "one_nibble() true"
);

@rows = ();
for (1..3) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [['d']],
   'single row table'
) or diag(Dumper(\@rows));

# ############################################################################
# empty table
# ############################################################################
$dbh->do('truncate table test.t');
$ni = make_nibble_iter(
   db       => 'test',
   tbl      => 't',
   argv     => [qw(--databases test --chunk-size 100)],
);

@rows = ();
for (1..3) {
   push @rows, $ni->next();
}
is_deeply(
   \@rows,
   [],
   'empty table'
) or diag(Dumper(\@rows));

# ############################################################################
# Callbacks
# ############################################################################
$ni = make_nibble_iter(
   sql_file  => "a-z.sql",
   db        => 'test',
   tbl       => 't',
   argv      => [qw(--databases test --chunk-size 2)],
   callbacks => {
      init          => sub { print "init\n" },
      after_nibble  => sub { print "after nibble ".$ni->nibble_number()."\n" },
      done          => sub { print "done\n" },
   }
);

$dbh->do('delete from test.t limit 20');  # 6 rows left

my $output = output(
   sub {
      for (1..8) { $ni->next() }
   },
);

is(
   $output,
"init
after nibble 1
after nibble 2
after nibble 3
done
done
",
   "callbacks"
);

# Test that init callback can stop nibbling.
$ni = make_nibble_iter(
   db        => 'test',
   tbl       => 't',
   argv      => [qw(--databases test --chunk-size 2)],
   callbacks => {
      init          => sub { print "init\n"; return 0; },
      after_nibble  => sub { print "after nibble\n"; },
      done          => sub { print "done\n"; },
   }
);

$dbh->do('delete from test.t limit 20');  # 6 rows left

$output = output(
   sub {
      for (1..8) { $ni->next() }
   },
);

is(
   $output,
"init
",
   "init callbacks can stop nibbling"
);

# ############################################################################
# Nibble a larger table by numeric pk id
# ############################################################################
$ni = make_nibble_iter(
   db       => 'sakila',
   tbl      => 'payment',
   argv     => [qw(--databases sakila --tables payment --chunk-size 100)],
);

my $n_nibbles = 0;
$n_nibbles++ while $ni->next();
is(
   $n_nibbles,
   16049,
   "Nibble sakila.payment (16049 rows)"
);

my $tbl = {
   db         => 'sakila',
   tbl        => 'country',
   tbl_struct => $tp->parse(
      $tp->get_create_table($dbh, 'sakila', 'country')),
};
my $chunk_checksum = $rc->make_chunk_checksum(
   dbh => $dbh,
   tbl => $tbl,
);
$ni = make_nibble_iter(
   db     => 'sakila',
   tbl    => 'country',
   argv   => [qw(--databases sakila --tables country --chunk-size 25)],
   select => $chunk_checksum,
);

my $row = $ni->next();
is_deeply(
   $row,
   [25, 'd9c52498'],
   "SELECT chunk checksum 1 FROM sakila.country"
) or diag(Dumper($row));

$row = $ni->next();
is_deeply(
   $row,
   [25, 'ebdc982c'],
   "SELECT chunk checksum 2 FROM sakila.country"
) or diag(Dumper($row));

$row = $ni->next();
is_deeply(
   $row,
   [25, 'e8d9438d'],
   "SELECT chunk checksum 3 FROM sakila.country"
) or diag(Dumper($row));

$row = $ni->next();
is_deeply(
   $row,
   [25, '2e3b895d'],
   "SELECT chunk checksum 4 FROM sakila.country"
) or diag(Dumper($row));

$row = $ni->next();
is_deeply(
   $row,
   [9, 'bd08fd55'],
   "SELECT chunk checksum 5 FROM sakila.country"
) or diag(Dumper($row));

# #########################################################################
# exec_nibble callback and explain_sth
# #########################################################################
my @expl;
$ni = make_nibble_iter(
   db     => 'sakila',
   tbl    => 'country',
   argv   => [qw(--databases sakila --tables country --chunk-size 60)],
   select => $chunk_checksum,
   callbacks => {
      exec_nibble  => sub {
         my (%args) = @_;
         my $nibble_iter = $args{NibbleIterator};
         my $sth         = $nibble_iter->statements();
         my $boundary    = $nibble_iter->boundaries();
         $sth->{explain_nibble}->execute(
            @{$boundary->{lower}}, @{$boundary->{upper}});
         push @expl, $sth->{explain_nibble}->fetchrow_hashref();
         return 0;
      },
   },
   one_nibble => 0,
);
$ni->next();
$ni->next();
ok($expl[0]->{rows} > 40 && $expl[0]->{rows} < 80, 'Rows between 40-80');
is($expl[0]->{key}, 'PRIMARY', 'Uses PRIMARY key');
is($expl[0]->{key_len}, '2', 'Uses 2 bytes of index');
is($expl[0]->{type} , 'range', 'Uses range type');

# #########################################################################
# film_actor, multi-column pk
# #########################################################################
$ni = make_nibble_iter(
   db       => 'sakila',
   tbl      => 'film_actor',
   argv     => [qw(--tables sakila.film_actor --chunk-size 1000)],
);

$n_nibbles = 0;
$n_nibbles++ while $ni->next();
is(
   $n_nibbles,
   5462,
   "Nibble sakila.film_actor (multi-column pk)"
);

is_deeply(
   $ni->sql(),
   {
      boundaries => {
         '<' => '((`actor_id` < ?) OR (`actor_id` = ? AND `film_id` < ?))',
         '<=' => '((`actor_id` < ?) OR (`actor_id` = ? AND `film_id` <= ?))',
         '>' => '((`actor_id` > ?) OR (`actor_id` = ? AND `film_id` > ?))',
         '>=' => '((`actor_id` > ?) OR (`actor_id` = ? AND `film_id` >= ?))'
      },
      columns  => [qw(actor_id actor_id film_id)],
      from     => '`sakila`.`film_actor` FORCE INDEX(`PRIMARY`)',
      where    => undef,
      order_by => '`actor_id`, `film_id`',
   },
   "sql()"
);

$ni = make_nibble_iter(
   db       => 'sakila',
   tbl      => 'address',
   argv     => [qw(--tables sakila.address --chunk-size 10),
                '--ignore-columns', 'phone,last_update'],
);

$ni->next();
is(
   $ni->statements()->{nibble}->{Statement},
   "SELECT `address_id`, `address`, `address2`, `district`, `city_id`, `postal_code` FROM `sakila`.`address` FORCE INDEX(`PRIMARY`) WHERE ((`address_id` >= ?)) AND ((`address_id` <= ?)) /*nibble table*/",
   "--ignore-columns"
);

# #########################################################################
# Put ORDER BY in nibble SQL.
# #########################################################################
$ni = make_nibble_iter(
   db       => 'sakila',
   tbl      => 'film_actor',
   order_by => 1,
   argv     => [qw(--tables sakila.film_actor --chunk-size 1000)],
);

$ni->next();

is(
   $ni->statements()->{nibble}->{Statement},
   "SELECT `actor_id`, `film_id`, `last_update` FROM `sakila`.`film_actor` FORCE INDEX(`PRIMARY`) WHERE ((`actor_id` > ?) OR (`actor_id` = ? AND `film_id` >= ?)) AND ((`actor_id` < ?) OR (`actor_id` = ? AND `film_id` <= ?)) ORDER BY `actor_id`, `film_id` /*nibble table*/",
   "Add ORDER BY to nibble SQL"
);

# ############################################################################
# Reset chunk size on-the-fly. 
# ############################################################################
$ni = make_nibble_iter(
   sql_file  => "a-z.sql",
   db        => 'test',
   tbl       => 't',
   argv      => [qw(--databases test --chunk-size 5)],
);

@rows = ();
my $i = 0;
while (my $row = $ni->next()) {
   push @{$rows[$ni->nibble_number()]}, @$row;
   if ( ++$i == 5 ) {
      $ni->set_chunk_size(20);
   }
}

is_deeply(
   \@rows,
   [
      undef,          # no 0 nibble
      [ ('a'..'e') ], # nibble 1
      [ ('f'..'y') ], # nibble 2, should contain 20 chars
      [ 'z'        ], # last nibble
   ],
   "Change chunk size while nibbling"
) or diag(Dumper(\@rows));

# ############################################################################
# Nibble one row at a time.
# ############################################################################
$ni = make_nibble_iter(
   sql_file  => "a-z.sql",
   db        => 'test',
   tbl       => 't',
   argv      => [qw(--databases test --chunk-size 1)],
);

@rows = ();
while (my $row = $ni->next()) {
   push @rows, @$row;
}

is_deeply(
   \@rows,
   [ ('a'..'z') ],
   "Nibble by 1 row"
);

# ############################################################################
# Avoid infinite loops.
# ############################################################################
$sb->load_file('master', "$in/bad_tables.sql");
$dbh->do('analyze table bad_tables.inv');
$ni = make_nibble_iter(
   db   => 'bad_tables',
   tbl  => 'inv',
   argv => [qw(--databases bad_tables --chunk-size 3)],
);

$all_rows = $dbh->selectall_arrayref('select * from bad_tables.inv order by tee_id, on_id');

is(
   $ni->nibble_index(),
   'index_inv_on_tee_id_and_on_id',
   'Use index with higest cardinality'
);

@rows = ();
while (my $row = $ni->next()) {
   push @rows, $row;
}

is_deeply(
   \@rows,
   $all_rows,
   'Selected all rows from non-unique index'
);

$dbh->do('alter table bad_tables.inv drop index index_inv_on_tee_id_and_on_id');
$ni = make_nibble_iter(
   db   => 'bad_tables',
   tbl  => 'inv',
   argv => [qw(--databases bad_tables --chunk-size 3)],
);

is(
   $ni->nibble_index(),
   'index_inv_on_on_id',
   'Using bad index'
);

throws_ok(
   sub { for (1..50) { $ni->next() } },
   qr/infinite loop/,
   'Detects infinite loop'
);

# ############################################################################
# Nibble small tables without indexes.
# ############################################################################
$ni = make_nibble_iter(
   sql_file => "a-z.sql",
   db       => 'test',
   tbl      => 't',
   argv     => [qw(--databases test --chunk-size 100)],
);
$dbh->do('alter table test.t drop index c');

@rows = ();
while (my $row = $ni->next()) {
   push @rows, @$row;
}

is_deeply(
   \@rows,
   [ ('a'..'z') ],
   "Nibble small table without indexes"
);

# ############################################################################
# Auto-select best index if wanted index doesn't exit.
# ############################################################################
$ni = make_nibble_iter(
   sql_file   => "a-z.sql",
   db         => 'test',
   tbl        => 't',
   one_nibble => 0,
   argv       => [qw(--databases test --chunk-index nonexistent)],
);

is(
   $ni->nibble_index(),
   'c',
   "Auto-chooses index if wanted index does not exist"
);

# ############################################################################
# Add a WHERE clause and nibble just the selected range.
# ############################################################################
$ni = make_nibble_iter(
   sql_file   => "a-z.sql",
   db         => 'test',
   tbl        => 't',
   one_nibble => 0,
   argv       => [qw(--databases test --where c>'m')],
);
$dbh->do('analyze table test.t');

@rows = ();
while (my $row = $ni->next()) {
   push @rows, @$row;
}

is_deeply(
   \@rows,
   [ ('n'..'z') ],
   "Nibbles only values in --where clause range"
);

$ni = make_nibble_iter(
   sql_file   => "a-z.sql",
   db         => 'test',
   tbl        => 't',
   one_nibble => 1,
   argv       => [qw(--databases test --where c>'m')],
);
1 while $ni->next();
my $sql = $ni->statements()->{nibble}->{Statement};
is(
   $sql,
   "SELECT `c` FROM `test`.`t` WHERE c>'m' /*bite table*/",
   "One nibble SQL with where"
);

# The real number of rows is 13, but MySQL may estimate a little.
cmp_ok(
   $ni->row_estimate(),
   '<=',
   15,
   "row_estimate()"
);

# ############################################################################
# Empty table.
# ############################################################################
$ni = make_nibble_iter(
   db         => 'mysql',
   tbl        => 'columns_priv',
   argv       => [qw(--tables mysql.columns_priv --chunk-size-limit 0)],
);

@rows = ();
while (my $row = $ni->next()) {
   push @rows, @$row;
}

is_deeply(
   \@rows,
   [ ],
   "--chunk-size-limit 0 on empty table"
);

# ############################################################################
# Resume.
# ############################################################################
$ni = make_nibble_iter(
   sql_file => "a-z.sql",
   db       => 'test',
   tbl      => 't',
   argv     => [qw(--databases test --chunk-size 5)],
   resume   => { lower_boundary => 'a', upper_boundary => 'e' },
);

@rows = ();
while (my $row = $ni->next()) {
   push @rows, @$row;
}

is_deeply(
   \@rows,
   [ ('f'..'z') ],
   "Resume from middle"
);

$ni = make_nibble_iter(
   sql_file => "a-z.sql",
   db       => 'test',
   tbl      => 't',
   argv     => [qw(--databases test --chunk-size 5)],
   resume   => { lower_boundary => 'z', upper_boundary => 'z' },
);

@rows = ();
while (my $row = $ni->next()) {
   push @rows, @$row;
}

is_deeply(
   \@rows,
   [ ],
   "Resume from end"
);

# #############################################################################
# Customize bite and nibble statement comments.
# #############################################################################
$ni = make_nibble_iter(
   db       => 'sakila',
   tbl      => 'address',
   argv     => [qw(--tables sakila.address --chunk-size 10)],
   comments => {
      bite   => "my bite",
      nibble => "my nibble",
   }
);

$ni->next();
is(
   $ni->statements()->{nibble}->{Statement},
   "SELECT `address_id`, `address`, `address2`, `district`, `city_id`, `postal_code`, `phone`, `last_update` FROM `sakila`.`address` FORCE INDEX(`PRIMARY`) WHERE ((`address_id` >= ?)) AND ((`address_id` <= ?)) /*my nibble*/",
   "Custom nibble comment"
);

$ni = make_nibble_iter(
   db       => 'sakila',
   tbl      => 'address',
   argv     => [qw(--tables sakila.address --chunk-size 1000)],
   comments => {
      bite   => "my bite",
      nibble => "my nibble",
   }
);

$ni->next();
is(
   $ni->statements()->{nibble}->{Statement},
   "SELECT `address_id`, `address`, `address2`, `district`, `city_id`, `postal_code`, `phone`, `last_update` FROM `sakila`.`address` /*my bite*/",
   "Custom bite comment"
);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/995274
# Index case-sensitivity.
# #############################################################################
$sb->load_file('master', "t/pt-table-checksum/samples/undef-arrayref-bug-995274.sql");

eval {
   $ni = make_nibble_iter(
      db   => 'test',
      tbl  => 'GroupMembers',
      argv => [qw(--databases test --chunk-size 100)],
   );
};
is(
   $EVAL_ERROR,
   '',
   "Bug 995274: no error creating nibble iter"
);

is_deeply(
   $ni->next(),
   ['450876', '3','691360'],
   "Bug 995274: nibble iter works"
);


# #############################################################################
# pt-table-checksum doesn't use non-unique index with highest cardinality
# https://bugs.launchpad.net/percona-toolkit/+bug/1199591
# #############################################################################

diag(`/tmp/12345/use < $trunk/t/lib/samples/cardinality.sql >/dev/null`);

$ni = make_nibble_iter(
   db   => 'cardb',
   tbl  => 't',
   argv => [qw(--databases cardb --chunk-size 2)],
);

is(
   $ni->{index},
   'b',
   "Use non-unique index with highest cardinality (bug 1199591)"
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
done_testing;
