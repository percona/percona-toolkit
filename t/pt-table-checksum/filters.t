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

use Data::Dumper;
use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 9;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 


# ############################################################################
# The schema object filters don't need to be tested extensively here
# because they should be tested extensively in SchemaIterator.t.
# ############################################################################

sub test_filter {
   my ($filters, $tbls) = @_;

   my $output = output(
      sub { pt_table_checksum::main(@args, '--explain', @$filters) },
   );
   my @got_tbls = $output =~ m/^-- (\S+)$/gm;
   is_deeply(
      \@got_tbls,
      $tbls,
      join(' ', @$filters),
   ) or print STDERR Dumper(\@got_tbls);
}

# sakila db has serval views where are (should be) automatically filtered out.
test_filter(
   [qw(--databases sakila)],
   [qw(
      sakila.actor
      sakila.address
      sakila.category
      sakila.city
      sakila.country
      sakila.customer
      sakila.film
      sakila.film_actor
      sakila.film_category
      sakila.film_text
      sakila.inventory
      sakila.language
      sakila.payment
      sakila.rental
      sakila.staff
      sakila.store
   )],
);

test_filter(
   [qw(--tables actor)],
   ['sakila.actor'],
);

test_filter(
   [qw(--tables sakila.actor)],
   ['sakila.actor'],
);

test_filter(
   ['--tables', 'actor,film'],
   ['sakila.actor', 'sakila.film'],
);

test_filter(
   ['--tables', 'sakila.actor,mysql.user'],
   ['mysql.user', 'sakila.actor'],
);

test_filter(
   [qw(-d sakila --engines MyISAM)],
   ['sakila.film_text'],
);

test_filter(
   [qw(-d sakila --engines myisam)],
   ['sakila.film_text'],
);

test_filter(
   [qw(--databases sakila --ignore-tables),
      'sakila.actor,sakila.address,category,city,payment'
   ],
   [qw(
      sakila.country
      sakila.customer
      sakila.film
      sakila.film_actor
      sakila.film_category
      sakila.film_text
      sakila.inventory
      sakila.language
      sakila.rental
      sakila.staff
      sakila.store
   )],
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
