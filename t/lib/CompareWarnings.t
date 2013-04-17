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

use Quoter;
use QueryParser;
use ReportFormatter;
use Transformers;
use DSNParser;
use Sandbox;
use CompareWarnings;
use PerconaTest;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master', {no_lc=>1});

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}
else {
   plan tests => 21;
}

$sb->create_dbs($dbh, ['test']);

Transformers->import(qw(make_checksum));

my $q  = new Quoter();
my $qp = new QueryParser();
my %modules = (
   Quoter      => $q,
   QueryParser => $qp,
);

my $cw;
my $report;
my @events;
my $hosts = [
   { dbh => $dbh, name => 'dbh-1' },
   { dbh => $dbh, name => 'dbh-2'  },
];

sub proc {
   my ( $when, %args ) = @_;
   die "I don't know when $when is"
      unless $when eq 'before_execute'
          || $when eq 'execute'
          || $when eq 'after_execute';
   for my $i ( 0..$#events ) {
      $events[$i] = $cw->$when(
         event    => $events[$i],
         dbh      => $hosts->[$i]->{dbh},
         %args,
      );
   }
};

sub get_id {
   return make_checksum(@_);
}

# #############################################################################
# Test it.
# #############################################################################

diag(`/tmp/12345/use < $trunk/t/lib/samples/compare-warnings.sql`);

@events = (
   {
      arg         => 'select * from test.t',
      fingerprint => 'select * from test.t',
      sampleno    => 1,
   },
   {
      arg         => 'select * from test.t',
      fingerprint => 'select * from test.t',
      sampleno    => 1,
   },
);

$cw = new CompareWarnings(
   'clear-warnings'       => 1,
   'clear-warnings-table' => 'mysql.bad',
   get_id => \&get_id,
   %modules,
);

isa_ok($cw, 'CompareWarnings');

eval {
   $cw->before_execute(
      event => $events[0],
      dbh   => $dbh,
   );
};

like(
   $EVAL_ERROR,
   qr/^Failed/,
   "Can't clear warnings with bad table"
);

$cw = new CompareWarnings(
   'clear-warnings' => 1,
   get_id => \&get_id,
   %modules,
);

eval {
   $cw->before_execute(
      event => { arg => 'select * from bad.db' },
      dbh   => $dbh,
   );
};

like(
   $EVAL_ERROR,
   qr/^Failed/,
   "Can't clear warnings with query with bad tables"
);

proc('before_execute', db=>'test');

$events[0]->{Query_time} = 123;
proc('execute');

is(
   $events[0]->{Query_time},
   123,
   "execute() doesn't execute if Query_time already exists"
);

ok(
   exists $events[1]->{Query_time}
   && $events[1]->{Query_time} >= 0,
   "execute() will execute if Query_time doesn't exist ($events[1]->{Query_time})"
);

proc('after_execute');

is(
   $events[0]->{warning_count},
   0,
   'Zero warning count'
);

is_deeply(
   $events[0]->{warnings},
   {},
   'No warnings'
);


# #############################################################################
# Test with the same warning on both hosts.
# #############################################################################
@events = (
   {
      arg         => "insert into test.t values (-2,'hi2',2)",
      fingerprint => 'insert into test.t values (?,?,?)',
      sampleno    => 1,
   },
   {
      arg         => "insert into test.t values (-2,'hi2',2)",
      fingerprint => 'insert into test.t values (?,?,?)',
      sampleno    => 1,
   },
);

proc('before_execute');
proc('execute');
proc('after_execute');

ok(
   $events[0]->{warning_count} == 1 && $events[1]->{warning_count} == 1,
   'Both events had 1 warning'
);

is_deeply(
   $events[0]->{warnings},
   {
      '1264' => {
         Code    => '1264',
         Level   => 'Warning',
         Message => 'Out of range value for column \'i\' at row 1'
      }
   },
   'Event 0 has 1264 warning'
);

is_deeply(
   $events[1]->{warnings},
   {
      '1264' => {
         Code    => '1264',
         Level   => 'Warning',
         Message => 'Out of range value for column \'i\' at row 1'
      }
   },
   'Event 1 has same 1264 warning'
);

# Compare the warnings: there should be no diffs since they're the same.
is_deeply(
   [ $cw->compare(events => \@events, hosts => $hosts) ],
   [qw(
      different_warning_counts 0
      different_warnings       0
      different_warning_levels 0
   )],
   'compare(), no differences'
);

ok(
   !exists $events[0]->{warnings}
   && !exists $events[1]->{warnings},
   'compare() deletes the warnings hashes from the events'
);

# Add the warnings back with an increased level on the second event.
my $w1 = {
   '1264' => {
      Code    => '1264',
      Level   => 'Warning',
      Message => 'Out of range value for column \'i\' at row 1'
   },
};
my $w2 = {
   '1264' => {
      Code    => '1264',
      Level   => 'Error',  # diff
      Message => 'Out of range value for column \'i\' at row 1'
   },
};
%{$events[0]->{warnings}} = %{$w1};
%{$events[1]->{warnings}} = %{$w2};

is_deeply(
   [ $cw->compare(events => \@events, hosts => $hosts) ],
   [qw(
      different_warning_counts 0
      different_warnings       0
      different_warning_levels 1
   )],
   'compare(), same warnings but different levels'
);

$report = <<EOF;
# Warning level differences
# Query ID           Code host1   host2 Message
# ================== ==== ======= ===== ======================================
# 4336C4AAA4EEF76B-1 1264 Warning Error Out of range value for column 'i' at row 1
EOF

is(
   $cw->report(hosts => $hosts),
   $report,
   'report warning level difference'
);

$w2->{1264}->{Level} = 'Warning';
$cw->reset();

# Make like the warning didn't happen on the 2nd event.
%{$events[0]->{warnings}} = %{$w1};
$events[0]->{warning_count} = 1;
delete $events[1]->{warnings};
$events[1]->{warning_count} = 0;

is_deeply(
   [ $cw->compare(events => \@events, hosts => $hosts) ],
   [qw(
      different_warning_counts 1
      different_warnings       1
      different_warning_levels 0
   )],
   'compare(), warning only on event 0'
);

$report = <<EOF;
# New warnings
# Query ID           Host  Code Message
# ================== ===== ==== ==========================================
# 4336C4AAA4EEF76B-1 host1 1264 Out of range value for column 'i' at row 1

# Warning count differences
# Query ID           host1 host2
# ================== ===== =====
# 4336C4AAA4EEF76B-1     1     0
EOF

is(
   $cw->report(hosts => $hosts),
   $report,
   'report new warning on host 1'
);

# Make like the warning didn't happen on the first event;
delete $events[0]->{warnings};
$events[0]->{warning_count} = 0;
%{$events[1]->{warnings}} = %{$w2};
$events[1]->{warning_count} = 1;

is_deeply(
   [ $cw->compare(events => \@events, hosts => $hosts) ],
   [qw(
      different_warning_counts 1
      different_warnings       1
      different_warning_levels 0
   )],
   'compare(), warning only on event 1'
);

$report = <<EOF;
# New warnings
# Query ID           Host  Code Message
# ================== ===== ==== ==========================================
# 4336C4AAA4EEF76B-1 host2 1264 Out of range value for column 'i' at row 1

# Warning count differences
# Query ID           host1 host2
# ================== ===== =====
# 4336C4AAA4EEF76B-1     0     1
EOF

is(
   $cw->report(hosts => $hosts),
   $report,
   'report new warning on host 2'
);

is_deeply(
   [ $cw->samples('insert into test.t values (?,?,?)') ],
   [ '1', "insert into test.t values (-2,'hi2',2)" ],
   'samples()'
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $cw->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
