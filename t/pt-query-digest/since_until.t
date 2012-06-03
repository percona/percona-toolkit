#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 11;

use PerconaTest;
use Sandbox;
use DSNParser;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

my $run_with = "$trunk/bin/pt-query-digest --report-format=query_report --limit 10 $trunk/t/lib/samples/slowlogs/";

# #############################################################################
# Issue 154: Add --since and --until options to mk-query-digest
# #############################################################################

# --since
ok(
   no_diff($run_with.'slow033.txt --since 2009-07-28', "t/pt-query-digest/samples/slow033-since-yyyy-mm-dd.txt"),
   '--since 2009-07-28'
);

ok(
   no_diff($run_with.'slow033.txt --since 090727', "t/pt-query-digest/samples/slow033-since-yymmdd.txt"),
   '--since 090727'
);

# This test will fail come July 2014.
ok(
   no_diff($run_with.'slow033.txt --since 1825d', "t/pt-query-digest/samples/slow033-since-Nd.txt"),
   '--since 1825d (5 years ago)'
);

# --until
ok(
   no_diff($run_with.'slow033.txt --until 2009-07-27', "t/pt-query-digest/samples/slow033-until-date.txt"),
   '--until 2009-07-27'
);

ok(
   no_diff($run_with.'slow033.txt --until 090727', "t/pt-query-digest/samples/slow033-until-date.txt"),
   '--until 090727'
);

# The result file is correct: it's the one that has all quries from slow033.txt.
ok(
   no_diff($run_with.'slow033.txt --until 1d', "t/pt-query-digest/samples/slow033-since-Nd.txt"),
   '--until 1d'
);

# And one very precise --since --until.
ok(
   no_diff($run_with.'slow033.txt --since "2009-07-26 11:19:28" --until "090727 11:30:00"', "t/pt-query-digest/samples/slow033-precise-since-until.txt"),
   '--since "2009-07-26 11:19:28" --until "090727 11:30:00"'
);

SKIP: {
   skip 'Cannot connect to sandbox master', 2 unless $dbh;

   # The result file is correct: it's the one that has all quries from
   # slow033.txt.
   ok(
      no_diff($run_with.'slow033.txt --aux-dsn h=127.1,P=12345,u=msandbox,p=msandbox --since "\'2009-07-08\' - INTERVAL 7 DAY"', "t/pt-query-digest/samples/slow033-since-Nd.txt"),
      '--since "\'2009-07-08\' - INTERVAL 7 DAY"',
   );

   ok(
      no_diff($run_with.'slow033.txt --aux-dsn h=127.1,P=12345,u=msandbox,p=msandbox --until "\'2009-07-28\' - INTERVAL 1 DAY"', "t/pt-query-digest/samples/slow033-until-date.txt"),
      '--until "\'2009-07-28\' - INTERVAL 1 DAY"',
   );

   $sb->wipe_clean($dbh);
};

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
