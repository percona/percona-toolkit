#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use DSNParser;
use Sandbox;
use MaatkitTest;
use Progress;
use Transformers;
use Retry;
use CopyRowsInsertSelect;

Transformers->import(qw(secs_to_time));

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to MySQL';
  
}
elsif ( !@{$dbh->selectcol_arrayref('SHOW DATABASES LIKE "sakila"')} ) {
   plan skip_all => "Sandbox master does not have the sakila database";
}
else {
   plan tests => 8;
}

my $rr     = new Retry();
my $osc    = new CopyRowsInsertSelect(Retry => $rr);
my $msg    = sub { print "$_[0]\n"; };
my $output = "";

$sb->load_file("master", "common/t/samples/osc/tbl001.sql");
$dbh->do("USE osc");

$osc->copy(
   dbh        => $dbh,
   from_table => 'osc.t',
   to_table   => 'osc.__new_t',
   columns    => [qw(id c)],
   chunks     => ['1=1'],
   msg        => $msg,
);

my $rows = $dbh->selectall_arrayref("select id, c from __new_t order by id");
is_deeply(
   $rows,
   [ [1, 'a'], [2, 'b'], [3, 'c'], [4, 'd'], [5, 'e'], ],
   "One chunk copy"
) or print Dumper($rows);


$dbh->do("truncate table osc.__new_t");
$output = output( sub {
   $osc->copy(
      dbh          => $dbh,
      from_table   => 'osc.t',
      to_table     => 'osc.__new_t',
      columns      => [qw(id c)],
      chunks       => ['id < 4', 'id >= 4 AND id < 6'],
      msg          => $msg,
      print        => 1,
      engine_flags => 'LOCK IN SHARE MODE',
   );
});

ok(
   no_diff(
      $output,
      "common/t/samples/osc/copyins001.txt",
      cmd_output => 1,
   ),
   "Prints 2 SQL statments for the 2 chunks"
);

$rows = $dbh->selectall_arrayref("select id, c from __new_t order by id");
is_deeply(
   $rows,
   [],
   "Doesn't exec those statements if print is true"
);

$dbh->do('create table osc.city like sakila.city');
$dbh->do('alter table osc.city engine=myisam');
my $chunks = [
   "`city_id` <  '71'",
   "`city_id` >= '71'  AND `city_id` < '141'",
   "`city_id` >= '141' AND `city_id` < '211'",
   "`city_id` >= '211' AND `city_id` < '281'",
   "`city_id` >= '281' AND `city_id` < '351'",
   "`city_id` >= '351' AND `city_id` < '421'",
   "`city_id` >= '421' AND `city_id` < '491'",
   "`city_id` >= '491' AND `city_id` < '561'",
   "`city_id` >= '561'",
];
my $pr = new Progress(
   jobsize => scalar @$chunks,
   spec    => [qw(percentage 10)],
   name    => "Copy rows"
);

$output = output(
   sub { $osc->copy(
      dbh        => $dbh,
      from_table => 'sakila.city',
      to_table   => 'osc.city',
      columns    => [qw(city_id city country_id last_update)],
      chunks     => $chunks,
      msg        => $msg,
      Progress   => $pr,
   ); },
   stderr => 1,
);
$rows = $dbh->selectall_arrayref("select count(city_id) from osc.city");
is_deeply(
   $rows,
   [[600]],
   "Copied all 600 sakila.city rows"
) or print Dumper($rows);

like(
   $output,
   qr/Copy rows:\s+100% 00:00 remain/,
   "Reports copy progress if Progress obj given"
);


my $sleep_cnt = 0;

$dbh->do("truncate table osc.__new_t");
output( sub {
   $osc->copy(
      dbh        => $dbh,
      from_table => 'osc.t',
      to_table   => 'osc.__new_t',
      columns    => [qw(id c)],
      chunks     => ['id < 4', 'id >= 4 AND id < 6'],
      msg        => $msg,
      sleep      => sub { $sleep_cnt++; },
   );
});
is(
   $sleep_cnt,
   1,
   "Calls sleep callback after each chunk (except last chunk)"
);

eval {
   $output = output(sub { $osc->cleanup(); } );
};
ok(
   !$EVAL_ERROR && !$output,
   "cleanup() works but doesn't do anything"
);

# #############################################################################
# Done.
# #############################################################################
$output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $osc->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
$sb->wipe_clean($dbh);
exit;
