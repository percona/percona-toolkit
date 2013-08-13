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

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use Transformers;
use QueryReportFormatter;
use EventAggregator;
use QueryRewriter;
use QueryParser;
use Quoter;
use ReportFormatter;
use OptionParser;
use DSNParser;
use ReportFormatter;
use ExplainAnalyzer;
use Sandbox;
use PerconaTest;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master', {no_lc=>1});  # for explain sparkline

my ($result, $events, $expected);

my $q   = new Quoter();
my $qp  = new QueryParser();
my $qr  = new QueryRewriter(QueryParser=>$qp);
my $o   = new OptionParser(description=>'qrf');
my $ex  = new ExplainAnalyzer(QueryRewriter => $qr, QueryParser => $qp);

$o->get_specs("$trunk/bin/pt-query-digest");
my $qrf = new QueryReportFormatter(
   OptionParser    => $o,
   QueryRewriter   => $qr,
   QueryParser     => $qp,
   Quoter          => $q, 
   ExplainAnalyzer => $ex,
);

my $ea  = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
   attributes => {
      Query_time    => [qw(Query_time)],
      Lock_time     => [qw(Lock_time)],
      user          => [qw(user)],
      ts            => [qw(ts)],
      Rows_sent     => [qw(Rows_sent)],
      Rows_examined => [qw(Rows_examined)],
      db            => [qw(db)],
   },
);

isa_ok($qrf, 'QueryReportFormatter');

$result = $qrf->rusage();
like(
   $result,
   qr/^# \S+ user time, \S+ system time, \S+ rss, \S+ vsz/s,
   'rusage report',
);

$events = [
   {  ts            => '071015 21:43:52',
      cmd           => 'Query',
      user          => 'root',
      host          => 'localhost',
      ip            => '',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '8.000652',
      Lock_time     => '0.000109',
      Rows_sent     => 1,
      Rows_examined => 1,
      pos_in_log    => 1,
      db            => 'test3',
   },
   {  ts   => '071015 21:43:52',
      cmd  => 'Query',
      user => 'root',
      host => 'localhost',
      ip   => '',
      arg =>
         "INSERT IGNORE INTO articles (id, body,)VALUES(3558268,'sample text')",
      Query_time    => '1.001943',
      Lock_time     => '0.000145',
      Rows_sent     => 0,
      Rows_examined => 0,
      pos_in_log    => 2,
      db            => 'test1',
   },
   {  ts            => '071015 21:43:53',
      cmd           => 'Query',
      user          => 'bob',
      host          => 'localhost',
      ip            => '',
      arg           => "SELECT id FROM users WHERE name='bar'",
      Query_time    => '1.000682',
      Lock_time     => '0.000201',
      Rows_sent     => 1,
      Rows_examined => 2,
      pos_in_log    => 5,
      db            => 'test1',
   }
];

# Here's the breakdown of values for those three events:
# 
# ATTRIBUTE     VALUE     BUCKET  VALUE        RANGE
# Query_time => 8.000652  326     7.700558026  range [7.700558026, 8.085585927)
# Query_time => 1.001943  284     0.992136979  range [0.992136979, 1.041743827)
# Query_time => 1.000682  284     0.992136979  range [0.992136979, 1.041743827)
#               --------          -----------
#               10.003277         9.684831984
#
# Lock_time  => 0.000109  97      0.000108186  range [0.000108186, 0.000113596)
# Lock_time  => 0.000145  103     0.000144980  range [0.000144980, 0.000152229)
# Lock_time  => 0.000201  109     0.000194287  range [0.000194287, 0.000204002)
#               --------          -----------
#               0.000455          0.000447453
#
# Rows_sent  => 1         284     0.992136979  range [0.992136979, 1.041743827)
# Rows_sent  => 0         0       0
# Rows_sent  => 1         284     0.992136979  range [0.992136979, 1.041743827)
#               --------          -----------
#               2                 1.984273958
#
# Rows_exam  => 1         284     0.992136979  range [0.992136979, 1.041743827)
# Rows_exam  => 0         0       0 
# Rows_exam  => 2         298     1.964363355, range [1.964363355, 2.062581523) 
#               --------          -----------
#               3                 2.956500334

# I hand-checked these values with my TI-83 calculator.
# They are, without a doubt, correct.

foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics(apdex_t=>1);
$result = $qrf->header(
   ea      => $ea,
   select  => [ qw(Query_time Lock_time Rows_sent Rows_examined ts) ],
   orderby => 'Query_time',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report006.txt",
      cmd_output => 1,
   ),
   'Global (header) report'
);

$result = $qrf->event_report(
   ea => $ea,
   # "users" is here to try to cause a failure
   select => [ qw(Query_time Lock_time Rows_sent Rows_examined ts db user users) ],
   item    => 'select id from users where name=?',
   rank    => 1,
   orderby => 'Query_time',
   reason  => 'top',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report007.txt",
      cmd_output => 1,
   ),
   'Event report'
);

{
   # pt-query-digest prints negative byte offset
   # https://bugs.launchpad.net/percona-toolkit/+bug/887638

   # printf "%d" can't really handle large values in some systems.
   # Given a large enough log file, it will start printing
   # negative values. The workaround is to use %.f instead. I haven't
   # researched what the recommended solution for this is, but
   # it's such an uncommon case and that it's not worth the time.
   # This bug should really only affect 32-bit machines, and even then
   # only those were the underlaying compiler's printf("%d") coerces the
   # argument into a signed int.
   my $item = 'select id from users where name=?';
   local $ea->results->{samples}->{$item}->{pos_in_log} = 1e+33;

   $result = $qrf->event_report(
      ea => $ea,
      # "users" is here to try to cause a failure
      select => [ qw(Query_time Lock_time Rows_sent Rows_examined ts db user users) ],
      item    => $item,
      rank    => 1,
      orderby => 'Query_time',
      reason  => 'top',
   );

   unlike(
      $result,
      qr/at byte -/,
      "Bug 887638: pt-query-digest prints negative byte offset"
   );
}

$result = $qrf->chart_distro(
   ea     => $ea,
   attrib => 'Query_time',
   item   => 'select id from users where name=?',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report008.txt",
      cmd_output => 1,
   ),
   'Query_time distro'
);

SKIP: {
   skip 'Wider labels not used, not tested', 1;
$qrf = new QueryReportFormatter(label_width => 15);

$result = $qrf->event_report(
   $ea,
   # "users" is here to try to cause a failure
   select => [ qw(Query_time Lock_time Rows_sent Rows_examined ts db user users) ],
   where   => 'select id from users where name=?',
   rank    => 1,
   worst   => 'Query_time',
   reason  => 'top',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report017.txt",
      cmd_output => 1,
   ),
   'Event report with wider label'
);

$qrf = new QueryReportFormatter;
};

# ########################################################################
# This one is all about an event that's all zeroes.
# ########################################################################
$ea  = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
   attributes => {
      Query_time    => [qw(Query_time)],
      Lock_time     => [qw(Lock_time)],
      user          => [qw(user)],
      ts            => [qw(ts)],
      Rows_sent     => [qw(Rows_sent)],
      Rows_examined => [qw(Rows_examined)],
      db            => [qw(db)],
   },
);

$events = [
   {  bytes              => 30,
      db                 => 'mysql',
      ip                 => '127.0.0.1',
      arg                => 'administrator command: Connect',
      fingerprint        => 'administrator command: Connect',
      Rows_affected      => 0,
      user               => 'msandbox',
      Warning_count      => 0,
      cmd                => 'Admin',
      No_good_index_used => 'No',
      ts                 => '090412 11:00:13.118191',
      No_index_used      => 'No',
      port               => '57890',
      host               => '127.0.0.1',
      Thread_id          => 8,
      pos_in_log         => '0',
      Query_time         => '0',
      Error_no           => 0
   },
];

foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics(apdex_t=>1);

$result = $qrf->header(
   ea      => $ea,
   select  => [ qw(Query_time Lock_time Rows_sent Rows_examined ts) ],
   orderby => 'Query_time',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report018.txt",
      cmd_output => 1,
   ),
   'Global report with all zeroes'
);

$result = $qrf->event_report(
   ea     => $ea,
   select => [ qw(Query_time Lock_time Rows_sent Rows_examined ts db user users) ],
   item    => 'administrator command: Connect',
   rank    => 1,
   orderby => 'Query_time',
   reason  => 'top',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report009.txt",
      cmd_output => 1,
   ),
   'Event report with all zeroes'
);

# This used to cause illegal division by zero in some cases.
$result = $qrf->chart_distro(
   ea     => $ea,
   attrib => 'Query_time',
   item   => 'administrator command: Connect',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report019.txt",
      cmd_output => 1,
   ),
   'Chart distro with all zeroes'
);

# #############################################################################
# Test bool (Yes/No) pretty printing.
# #############################################################################
$events = [
   {  ts            => '071015 21:43:52',
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '8.000652',
      Lock_time     => '0.002300',
      QC_Hit        => 'No',
      Filesort      => 'Yes',
      InnoDB_IO_r_bytes     => 2,
      InnoDB_pages_distinct => 20,
   },
   {  ts            => '071015 21:43:52',
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '1.001943',
      Lock_time     => '0.002320',
      QC_Hit        => 'Yes',
      Filesort      => 'Yes',
      InnoDB_IO_r_bytes     => 2,
      InnoDB_pages_distinct => 18,
   },
   {  ts            => '071015 21:43:53',
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='bar'",
      Query_time    => '1.000682',
      Lock_time     => '0.003301',
      QC_Hit        => 'Yes',
      Filesort      => 'Yes',
      InnoDB_IO_r_bytes     => 3,
      InnoDB_pages_distinct => 11,
   }
];

$ea  = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
   ignore_attributes => [qw(arg cmd)],
);
foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
$result = $qrf->header(
   ea      => $ea,
   orderby => 'Query_time',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report020.txt",
      cmd_output => 1,
   ),
   'Bool (Yes/No) pretty printer'
);

$events = [
   {  ts            => '071015 21:43:52',
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '8.000652',
      Lock_time     => '0.002300',
      QC_Hit        => 'No',
      Filesort      => 'No',
      InnoDB_IO_r_bytes     => 2,
      InnoDB_pages_distinct => 20,
   },
];
$ea->reset_aggregated_data();
foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();

$result = $qrf->header(
   ea      => $ea,
   orderby => 'Query_time',
);
ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report023.txt",
      cmd_output => 1,
   ),
   'No Boolean sub-header in gobal report when all zero bools'
);

$result = $qrf->event_report(
   ea      => $ea,
   orderby => 'Query_time',
   item    => 'select id from users where name=?',
);
ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report024.txt",
      cmd_output => 1,
   ),
   'No Boolean sub-header in event report with all zero bools'
);

# #############################################################################
# Test attrib sorting.
# #############################################################################

# This test uses the $ea from the Bool pretty printer test above.
my $sorted = $qrf->sort_attribs($ea);
is_deeply(
   $sorted,
   {
      num    => [qw(Query_time Lock_time)],
      innodb => [qw(InnoDB_IO_r_bytes InnoDB_pages_distinct)],
      bool   => [qw(Filesort QC_Hit)],
      string => [qw()],
   },
   'sort_attribs()'
) or print Dumper($sorted);

# Make an ea with most of the common attributes.
$events = [
   {  ts            => '071015 21:43:52',
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='foo'",
      bytes         => length("SELECT id FROM users WHERE name='foo'"),
      db            => "db1",
      user          => "myuser",
      host          => "127.0.0.1",
      Thread_id     => 555,
      Query_time    => '8.000652',
      Lock_time     => '0.002300',
      Rows_sent     => 100,
      Rows_examined => 5000000,
      Rows_read     => 123456789,
      QC_Hit        => 'No',
      Filesort      => 'Yes',
      Merge_passes  => 50,
      InnoDB_IO_r_bytes     => 2,
      InnoDB_pages_distinct => 20,
   },
];

$ea  = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
   ignore_attributes => [qw(arg cmd)],
   type_for => { Thread_id => 'string' },
);
foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();

$sorted = $qrf->sort_attribs($ea);
is_deeply(
   $sorted,
   {
      num    => [qw(Query_time Lock_time Rows_sent Rows_examined Rows_read Merge_passes bytes)],
      innodb => [qw(InnoDB_IO_r_bytes InnoDB_pages_distinct)],
      bool   => [qw(Filesort QC_Hit)],
      string => [qw(db host Thread_id user)],
   },
   'more sort_attribs()'
) or print Dumper($sorted);

# ############################################################################
# Test that --[no]zero-bool removes 0% vals.
# ############################################################################
$events = [
   {  ts            => '071015 21:43:52',
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '8.000652',
      Lock_time     => '0.002300',
      QC_Hit        => 'No',
      Filesort      => 'No',
   },
   {  ts            => '071015 21:43:52',
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '1.001943',
      Lock_time     => '0.002320',
      QC_Hit        => 'Yes',
      Filesort      => 'No',
   },
   {  ts            => '071015 21:43:53',
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='bar'",
      Query_time    => '1.000682',
      Lock_time     => '0.003301',
      QC_Hit        => 'Yes',
      Filesort      => 'No',
   }
];

$ea  = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
   ignore_attributes => [qw(arg cmd)],
);
foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
$result = $qrf->header(
   ea        => $ea,
   # select    => [ $ea->get_attributes() ],
   orderby   => 'Query_time',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report021.txt",
      cmd_output => 1,
   ),
   'No zero bool vals'
);

# #############################################################################
# Issue 458: mk-query-digest Use of uninitialized value in division (/) at
# line 3805
# #############################################################################
use SlowLogParser;
my $p = new SlowLogParser();

sub report_from_file {
   my $ea2 = new EventAggregator(
      groupby => 'fingerprint',
      worst   => 'Query_time',
   );
   my ( $file ) = @_;
   $file = "$trunk/$file";
   my @e;
   my @callbacks;
   push @callbacks, sub {
      my ( $event ) = @_;
      my $group_by_val = $event->{arg};
      return 0 unless defined $group_by_val;
      $event->{fingerprint} = $qr->fingerprint($group_by_val);
      return $event;
   };
   push @callbacks, sub {
      $ea2->aggregate(@_);
   };
   eval {
      open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
      my %args = (
         next_event => sub { return <$fh>;      },
         tell       => sub { return tell($fh);  },
      );
      while ( my $e = $p->parse_event(%args) ) {
         $_->($e) for @callbacks;
      }
      close $fh;
   };
   die $EVAL_ERROR if $EVAL_ERROR;
   $ea2->calculate_statistical_metrics();
   my %top_spec = (
      attrib  => 'Query_time',
      orderby => 'sum',
      total   => 100,
      count   => 100,
   );
   my ($worst, $other) = $ea2->top_events(%top_spec);
   my $top_n = scalar @$worst;
   my $report = '';
   foreach my $rank ( 1 .. $top_n ) {
      $report .= $qrf->event_report(
         ea      => $ea2,
         # select  => [ $ea2->get_attributes() ],
         item    => $worst->[$rank - 1]->[0],
         rank    => $rank,
         orderby => 'Query_time',
         reason  => '',
      );
   }
   return $report;
}

# The real bug is in QueryReportFormatter, and there's nothing particularly
# interesting about this sample, but we just want to make sure that the
# timestamp prop shows up only in the one event.  The bug is that it appears
eval {
   report_from_file('t/lib/samples/slowlogs/slow029.txt');
};
is(
   $EVAL_ERROR,
   '',
   'event_report() does not die on empty attributes (issue 458)'
);

# #############################################################################
# Test that format_string_list() truncates long strings.
# #############################################################################

$events = [
   {  ts   => '071015 21:43:52',
      cmd  => 'Query',
      arg  => "SELECT id FROM users WHERE name='foo'",
      Query_time => 1,
      foo  => "Hi.  I'm a very long string.  I'm way over the 78 column width that we try to keep lines limited to so text wrapping doesn't make things look all funky and stuff.",
   },
];

$ea  = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
   ignore_attributes => [qw(arg cmd)],
);
foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
$result = $qrf->event_report(
   ea      => $ea,
   select  => [ qw(Query_time foo) ],
   item    => 'select id from users where name=?',
   rank    => 1,
   orderby => 'Query_time',
   reason  => 'top',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report010.txt",
      cmd_output => 1,
   ),
   "Don't truncate one long string"
);

$ea->reset_aggregated_data();
push @$events,
   {  ts   => '071015 21:43:55',
      cmd  => 'Query',
      arg  => "SELECT id FROM users WHERE name='foo'",
      Query_time => 2,
      foo  => "Me too! I'm a very long string yay!  I'm also over the 78 column width that we try to keep lines limited to."
   };

foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
$result = $qrf->event_report(
   ea      => $ea,
   select  => [ qw(Query_time foo) ],
   item    => 'select id from users where name=?',
   rank    => 1,
   orderby => 'Query_time',
   reason  => 'top',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report011.txt",
      cmd_output => 1,
   ),
   "Don't truncate multiple long strings"
);

$ea->reset_aggregated_data();
push @$events,
   {  ts   => '071015 21:43:55',
      cmd  => 'Query',
      arg  => "SELECT id FROM users WHERE name='foo'",
      Query_time => 3,
      foo  => 'Number 3 long string, but I\'ll exceed the line length so I\'ll only show up as "more" :-('
   };

foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
$result = $qrf->event_report(
   ea      => $ea,
   select  => [ qw(Query_time foo) ],
   item    => 'select id from users where name=?',
   rank    => 1,
   orderby => 'Query_time',
   reason  => 'top',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report012.txt",
      cmd_output => 1,
   ),
   "Don't truncate multiple strings longer than whole line"
);

# #############################################################################
# Issue 478: mk-query-digest doesn't count errors and hosts right
# #############################################################################

# We decided that string attribs shouldn't be listed in the global header.
$events = [
   {
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '8.000652',
      user          => 'bob',
   },
   {
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '1.001943',
      user          => 'bob',
   },
   {
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='bar'",
      Query_time    => '1.000682',
      user          => 'bob',
   }
];

$ea  = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
   ignore_attributes => [qw(arg cmd)],
);
foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
$result = $qrf->header(
   ea      => $ea,
   select  => $ea->get_attributes(),
   orderby => 'Query_time',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report022.txt",
      cmd_output => 1,
   ),
   'No string attribs in global report (issue 478)'
);

# #############################################################################
# Issue 744: Option to show all Hosts
# #############################################################################

# Don't shorten IP addresses.
$events = [
   {
      cmd        => 'Query',
      arg        => "foo",
      Query_time => '8.000652',
      host       => '123.123.123.456',
   },
   {
      cmd        => 'Query',
      arg        => "foo",
      Query_time => '8.000652',
      host       => '123.123.123.789',
   },
];

$ea  = new EventAggregator(
   groupby => 'arg',
   worst   => 'Query_time',
   ignore_attributes => [qw(arg cmd)],
);
foreach my $event (@$events) {
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
$result = $qrf->event_report(
   ea      => $ea,
   select  => [ qw(Query_time host) ],
   item    => 'foo',
   rank    => 1,
   orderby => 'Query_time',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report013.txt",
      cmd_output => 1,
   ),
   "IPs not shortened"
);

# Add another event so we get "... N more" to make sure that IPs
# are still not shortened.
push @$events, 
   {
      cmd        => 'Query',
      arg        => "foo",
      Query_time => '8.000652',
      host       => '123.123.123.999',
   };
$ea->aggregate($events->[-1]);
$ea->calculate_statistical_metrics();
$result = $qrf->event_report(
   ea      => $ea,
   select  => [ qw(Query_time host) ],
   item    => 'foo',
   rank    => 1,
   orderby => 'Query_time',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report014.txt",
      cmd_output => 1,
   ),
   "IPs not shortened with more"
);

$result = $qrf->event_report(
   ea       => $ea,
   select   => [ qw(Query_time host) ],
   item     => 'foo',
   rank     => 1,
   orderby  => 'Query_time',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report015.txt",
      cmd_output => 1,
   ),
   "Show all hosts"
);

# #############################################################################
# Issue 948: mk-query-digest treats InnoDB_rec_lock_wait value as number
# instead of time
# #############################################################################

$events = [
   {
      cmd        => 'Query',
      arg        => "foo",
      Query_time => '8.000652',
      InnoDB_rec_lock_wait => 0.001,
      InnoDB_IO_r_wait     => 0.002,
      InnoDB_queue_wait    => 0.003,
   },
];

$ea  = new EventAggregator(
   groupby => 'arg',
   worst   => 'Query_time',
   ignore_attributes => [qw(arg cmd)],
);
foreach my $event (@$events) {
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
$result = $qrf->event_report(
   ea      => $ea,
   select  => [ qw(Query_time InnoDB_rec_lock_wait InnoDB_IO_r_wait InnoDB_queue_wait) ],
   item    => 'foo',
   rank    => 1,
   orderby => 'Query_time',
);

ok(
   no_diff(
      $result,
      "t/lib/samples/QueryReportFormatter/report016.txt",
      cmd_output => 1,
   ),
   "_wait attribs treated as times (issue 948)"
);

# #############################################################################
# print_reports()
# #############################################################################
$events = [
   {
      cmd         => 'Query',
      arg         => "select col from tbl where id=42",
      fingerprint => "select col from tbl where id=?",
      Query_time  => '1.000652',
      Lock_time   => '0.001292',
      ts          => '071015 21:43:52',
      pos_in_log  => 123,
      db          => 'foodb',
   },
];
$ea = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
);
foreach my $event ( @$events ) {
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics(apdex_t=>1);

# Reset opts in case anything above left something set.
@ARGV = qw();
$o->get_opts();
$qrf = new QueryReportFormatter(
   OptionParser    => $o,
   QueryRewriter   => $qr,
   QueryParser     => $qp,
   Quoter          => $q, 
   ExplainAnalyzer => $ex,
);
# Normally, the report subs will make their own ReportFormatter but
# that package isn't visible to QueryReportFormatter right now so we
# make ReportFormatters and pass them in.  Since ReporFormatters can't
# be shared, we can only test one subreport at a time, else the
# prepared statements subreport will reuse/reprint stuff from the
# profile subreport.  And the line width is 82 because that's the new
# default to accommodate the EXPLAIN sparkline (issue 1141).
my $report = new ReportFormatter(line_width=>82);
$qrf->{formatter} = $report;
ok(
   no_diff(
      sub { $qrf->print_reports(
         reports    => [qw(header query_report profile)],
         ea         => $ea,
         worst      => [['select col from tbl where id=?','top',1]],
         other      => [],
         orderby    => 'Query_time',
         groupby    => 'fingerprint',
         variations => [qw(arg)],
      ); },
      "t/lib/samples/QueryReportFormatter/report001.txt",
   ),
   "print_reports(header, query_report, profile)"
);

ok(
   no_diff(
      sub { $qrf->print_reports(
         reports    => [qw(profile query_report header)],
         ea         => $ea,
         worst      => [['select col from tbl where id=?','top',1]],
         orderby    => 'Query_time',
         groupby    => 'fingerprint',
         variations => [qw(arg)],
      ); },
      "t/lib/samples/QueryReportFormatter/report003.txt",
   ),
   "print_reports(profile, query_report, header)",
);

$events = [
   {
      Query_time    => '0.000286',
      Warning_count => 0,
      arg           => 'PREPARE SELECT i FROM d.t WHERE i=?',
      fingerprint   => 'prepare select i from d.t where i=?',
      bytes         => 35,
      cmd           => 'Query',
      db            => undef,
      pos_in_log    => 0,
      ts            => '091208 09:23:49.637394',
      Statement_id  => 2,
   },
   {
      Query_time    => '0.030281',
      Warning_count => 0,
      arg           => 'EXECUTE SELECT i FROM d.t WHERE i="3"',
      fingerprint   => 'execute select i from d.t where i=?',
      bytes         => 37,
      cmd           => 'Query',
      db            => undef,
      pos_in_log    => 1106,
      ts            => '091208 09:23:49.637892',
      Statement_id  => 2,
   },
];
$ea = new EventAggregator(
   groupby  => 'fingerprint',
   worst    => 'Query_time',
   type_for => {
      Statement_id => 'string',
   },
);
foreach my $event ( @$events ) {
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
ok(
   no_diff(
      sub {
         $qrf->print_reports(
            reports => ['query_report','prepared'],
            ea      => $ea,
            worst   => [
               ['execute select i from d.t where i=?', 'top',1],
               ['prepare select i from d.t where i=?', 'top',2],
            ],
            orderby    => 'Query_time',
            groupby    => 'fingerprint',
            variations => [qw(arg)],
         );
      },
      "t/lib/samples/QueryReportFormatter/report002.txt",
   ),
   "print_reports(query_report, prepared)"
);

push @$events,
   {
      Query_time    => '1.030281',
      arg           => 'update foo set col=1 where 1',
      fingerprint   => 'update foo set col=? where ?',
      bytes         => 37,
      cmd           => 'Query',
      pos_in_log    => 100,
      ts            => '091208 09:23:49.637892',
   },
$ea = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
);
foreach my $event ( @$events ) {
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
ok(
   no_diff(
      sub {
         $qrf->print_reports(
            reports => ['profile'],
            ea      => $ea,
            worst   => [
               ['update foo set col=? where ?', 'top',1]
            ],
            other => [
               ['execute select i from d.t where i=?','misc',2],
               ['prepare select i from d.t where i=?','misc',3],
            ],
            orderby => 'Query_time',
            groupby => 'fingerprint',
         );
      },
      "t/lib/samples/QueryReportFormatter/report004.txt",
   ),
   "MISC items in profile"
);

# #############################################################################
# EXPLAIN report
# #############################################################################
SKIP: {
   skip 'Cannot connect to sandbox master', 3 unless $dbh;
   $sb->load_file('master', "t/lib/samples/QueryReportFormatter/table.sql");

   @ARGV = qw(--explain F=/tmp/12345/my.sandbox.cnf);
   $o->get_opts();
   $qrf = new QueryReportFormatter(
      OptionParser    => $o,
      QueryRewriter   => $qr,
      QueryParser     => $qp,
      Quoter          => $q, 
      ExplainAnalyzer => $ex,
   );
   my $qrf = new QueryReportFormatter(
      OptionParser    => $o,
      QueryRewriter   => $qr,
      QueryParser     => $qp,
      Quoter          => $q, 
      dbh             => $dbh,
      ExplainAnalyzer => $ex,
   );

   my $explain = load_file(
        $sandbox_version eq '5.6' ? "t/lib/samples/QueryReportFormatter/report031.txt"
      : $sandbox_version ge '5.1' ? "t/lib/samples/QueryReportFormatter/report025.txt"
      :                             "t/lib/samples/QueryReportFormatter/report026.txt");

   is(
      $qrf->explain_report("select * from qrf.t where i=2", 'qrf'),
      $explain,
      "explain_report()"
   );

   $sb->wipe_clean($dbh);
   $dbh->disconnect();
}

# #############################################################################
# files and date reports.
# #############################################################################
like(
   $qrf->date(),
   qr/# Current date: .+?\d+:\d+:\d+/,
   "date report"
);

is(
   $qrf->files(files=>[{name=>"foo"},{name=>"bar"}]),
   "# Files: foo, bar\n",
   "files report"
);

like(
   $qrf->hostname(),
   qr/# Hostname: .+?/,
   "hostname report"
);

# #############################################################################
# Test report grouping.
# #############################################################################
$events = [
   {
      cmd         => 'Query',
      arg         => "select col from tbl where id=42",
      fingerprint => "select col from tbl where id=?",
      Query_time  => '1.000652',
      Lock_time   => '0.001292',
      ts          => '071015 21:43:52',
      pos_in_log  => 123,
      db          => 'foodb',
   },
];
$ea = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
);
foreach my $event ( @$events ) {
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
@ARGV = qw();
$o->get_opts();
$qrf    = new QueryReportFormatter(
   OptionParser    => $o,
   QueryRewriter   => $qr,
   QueryParser     => $qp,
   Quoter          => $q, 
   ExplainAnalyzer => $ex,
);
my $output = output(
   sub { $qrf->print_reports(
      reports => [qw(rusage date files header query_report profile)],
      ea      => $ea,
      worst   => [['select col from tbl where id=?','top',1]],
      orderby => 'Query_time',
      groupby => 'fingerprint',
      files   => [{name=>"foo"},{name=>"bar"}],
      group   => {map {$_=>1} qw(rusage date files header)},
   ); }
);
like(
   $output,
   qr/
^#\s.+?\suser time.+?vsz$
^#\sCurrent date:.+?$
^#\sFiles:\sfoo,\sbar$
   /mx,
   "grouped reports"
);

# #############################################################################
# Issue 1124: Make mk-query-digest profile include variance-to-mean ratio
# #############################################################################

$events = [
   {
      Query_time    => "1.000000",
      arg           => "select c from t where id=1",
      fingerprint   => "select c from t where id=?",
      cmd           => 'Query',
      pos_in_log    => 0,
   },
   {
      Query_time    => "5.500000",
      arg           => "select c from t where id=2",
      fingerprint   => "select c from t where id=?",
      cmd           => 'Query',
      pos_in_log    => 0,
   },
   {
      Query_time    => "2.000000",
      arg           => "select c from t where id=3",
      fingerprint   => "select c from t where id=?",
      cmd           => 'Query',
      pos_in_log    => 0,
   },
   {
      Query_time    => "9.000000",
      arg           => "select c from t where id=4",
      fingerprint   => "select c from t where id=?",
      cmd           => 'Query',
      pos_in_log    => 0,
   },
];
$ea = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
);
foreach my $event ( @$events ) {
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
ok(
   no_diff(
      sub {
         $qrf->print_reports(
            reports => ['profile'],
            ea      => $ea,
            worst   => [
               ['select c from t where id=?', 'top',1],
            ],
            orderby => 'Query_time',
            groupby => 'fingerprint',
         );
      },
      "t/lib/samples/QueryReportFormatter/report005.txt",
   ),
   "Variance-to-mean ration (issue 1124)"
);

# ############################################################################
# Bug 887688: Prepared statements crash pt-query-digest
# ############################################################################

# PREP without EXEC
$events = [
   {
      Query_time    => '0.000286',
      Warning_count => 0,
      arg           => 'PREPARE SELECT i FROM d.t WHERE i=?',
      fingerprint   => 'prepare select i from d.t where i=?',
      bytes         => 35,
      cmd           => 'Query',
      db            => undef,
      pos_in_log    => 0,
      ts            => '091208 09:23:49.637394',
      Statement_id  => 1,
   },
];
$ea = new EventAggregator(
   groupby  => 'fingerprint',
   worst    => 'Query_time',
   type_for => {
      Statement_id => 'string',
   },
);
foreach my $event ( @$events ) {
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
ok(
   no_diff(
      sub {
         $qrf->print_reports(
            reports => ['prepared'],
            ea      => $ea,
            worst   => [
               ['prepare select i from d.t where i=?', 'top', 1],
            ],
            orderby    => 'Query_time',
            groupby    => 'fingerprint',
            variations => [qw(arg)],
         );
      },
      "t/lib/samples/QueryReportFormatter/report030.txt",
   ),
   "PREP without EXEC (bug 887688)"
);

# #############################################################################
# Done.
# #############################################################################
$output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $qrf->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
