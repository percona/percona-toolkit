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
require "$trunk/bin/pt-find";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 21;
}

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-find -F $cnf ";

$output = `$cmd mysql --tblregex column`;
like($output, qr/`mysql`.`columns_priv`/, 'Found mysql.columns_priv');

$output = `$cmd mysql`;
like(
   $output,
   qr/`mysql`.`columns_priv`/,
   'Prints tables without any tests'
);

# These tests are going to be senstive to your sakila db.  Hopefully,
# it matches mine which I tend to load fresh and not modify.  For example,
# the next insert id for sakila.film is expected to be 1001.  If this
# becomes an issue, I may commit my copy of the sakila db to Google Code.

SKIP: {
   skip 'Sandbox master does not have the sakila database', 17
      unless @{$dbh->selectcol_arrayref('SHOW DATABASES LIKE "sakila"')};

   # ########################################################################
   # First, test actions: --exec*, print*, etc.
   # ########################################################################

   # POD says: "[--print] is the default action if no other action is
   # specified."
   $output = `$cmd --autoinc 1001`;
   is(
      $output,
      "`sakila`.`film`\n",
      '--print is default action'
   );


   # Test that explicit --print doesn't blow up. 
   $output = `$cmd --autoinc 1001 --print`;
   is(
      $output,
      "`sakila`.`film`\n",
      'Explicit --print',
   );

   # Test --column-*
   $output = `$cmd sakila  --column-name release_year --print`;
   is(
      $output,
      "`sakila`.`film`\n",
      '--column-name'
   );

   $output = `$cmd sakila --tbllike actor --column-type smallint --print`;
   is(
      $output,
      "`sakila`.`actor`\n",
      '--column-type'
   );

   # Test --view.
   $output = `$cmd sakila  --view 'left join \`film_category\`'  --print`;
   is(
      $output,
   "`sakila`.`actor_info`
`sakila`.`film_list`
`sakila`.`nicer_but_slower_film_list`\n",
      '--view that matches'
   );

   $output = `$cmd sakila  --view blah  --print`;
   is(
      $output,
      '',
      "--view that doesn't match"
   );

   # Test --procedure.
   $output = `$cmd sakila  --procedure min_monthly_purchases  --print`;
   is(
      $output,
      "`sakila`.`PROCEDURE rewards_report`\n",
      '--procedure that matches'
   );

   $output = `$cmd sakila  --procedure blah  --print`;
   is(
      $output,
      '',
      "--procedure that doesn't match"
   );

   # Test --function.
   $output = `$cmd sakila  --function v_out --print`;
   is(
      $output,
      "`sakila`.`FUNCTION inventory_in_stock`\n",
      '--function that matches'
   );

   $output = `$cmd sakila  --function blah  --print`;
   is(
      $output,
      '',
      "--function that doesn't match"
   );

   # Test --trigger without --trigger-table.
   $output = `$cmd sakila  --trigger 'UPDATE film_text' --print`;
   is(
      $output,
      "`sakila`.`UPDATE TRIGGER upd_film on film`\n",
      '--trigger that matches without --trigger-table'
   );

   $output = `$cmd sakila  --trigger blah  --print`;
   is(
      $output,
      '',
      "--trigger that doesn't match without --trigger-table"
   );

   # Test --trigger with --trigger-table.
   $output = `$cmd sakila  --trigger 'UPDATE film_text' --trigger-table film --print`;
   is(
      $output,
      "`sakila`.`UPDATE TRIGGER upd_film on film`\n",
      '--trigger that matches with matching --trigger-table'
   );

   $output = `$cmd sakila  --trigger blah --trigger-table film  --print`;
   is(
      $output,
      '',
      "--trigger that doesn't match with matching --trigger-table"
   );

   $output = `$cmd sakila  --trigger 'UPDATE film_text' --trigger-table foo --print`;
   is(
      $output,
      '',
      '--trigger that matches with non-matching --trigger-table'
   );

   $output = `$cmd sakila  --trigger blah --trigger-table foo --print`;
   is(
      $output,
      '',
      "--trigger that doesn't match with non-matching --trigger-table"
   );

   # Test NULL sizes.
   $output = `$cmd sakila  --datasize NULL`,
   is(
      $output,
"`sakila`.`actor_info`
`sakila`.`customer_list`
`sakila`.`film_list`
`sakila`.`nicer_but_slower_film_list`
`sakila`.`sales_by_film_category`
`sakila`.`sales_by_store`
`sakila`.`staff_list`
",
      '--datasize NULL',
   );
};

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
`touch /tmp/mk-script.pid`;
$output = `$cmd mysql --pid /tmp/mk-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-script.pid already exists},
   'Dies if PID file already exists (issue 391)'
);
`rm -rf /tmp/mk-script.pid`;


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
