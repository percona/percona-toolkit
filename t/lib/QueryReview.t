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

use Transformers;
use QueryReview;
use QueryRewriter;
use TableParser;
use Quoter;
use SlowLogParser;
use DSNParser;
use VersionParser;
use Sandbox;
use PerconaTest;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source', {no_lc=>1, AutoCommit => 1});

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}

$sb->create_dbs($dbh, ['test']);
$sb->load_file('source', "t/lib/samples/query_review.sql");
my $output = "";
my $qr = new QueryRewriter();
my $lp = new SlowLogParser;
my $q  = new Quoter();
my $tp = new TableParser(Quoter => $q);

my $tbl_struct = $tp->parse(
   $tp->get_create_table($dbh, 'test', 'query_review'));

my $qv = new QueryReview(
   dbh        => $dbh,
   db_tbl     => '`test`.`query_review`',
   tbl_struct => $tbl_struct,
   ts_default => "'2009-01-01'",
   quoter     => $q,
);

isa_ok($qv, 'QueryReview');

my $callback = sub {
   my ( $event ) = @_;
   my $fp = $qr->fingerprint($event->{arg});
   $qv->set_review_info(
      fingerprint => $fp,
      sample      => $event->{arg},
      first_seen  => $event->{ts},
      last_seen   => $event->{ts},
   );
};

my $event       = {};
my $more_events = 1;
my $log;
open $log, '<', "$trunk/t/lib/samples/slowlogs/slow006.txt" or die $OS_ERROR;
while ( $more_events ) {
   $event = $lp->parse_event(
      next_event => sub { return <$log>;    },
      tell       => sub { return tell $log; },
      oktorun    => sub { $more_events = $_[0]; },
   );
   $callback->($event) if $event;
}
close $log;
$more_events = 1;
open $log, '<', "$trunk/t/lib/samples/slowlogs/slow021.txt" or die $OS_ERROR;
while ( $more_events ) {
   $event = $lp->parse_event(
      next_event => sub { return <$log>;    },
      tell       => sub { return tell $log; },
      oktorun    => sub { $more_events = $_[0]; },
   );
   $callback->($event) if $event;
}
close $log;

my $res = $dbh->selectall_arrayref(
   'SELECT checksum, first_seen, last_seen FROM query_review order by checksum',
   { Slice => {} });
is_deeply(
   $res,
   [  {  checksum   => '3E4FB43148C4B07CD4CD74934382A184',
         last_seen  => '2007-12-18 11:49:07',
         first_seen => '2005-12-19 16:56:31'
      }, 
      {  checksum   => '538CA093E701E0CBA20C29AF174CE545',
         last_seen  => '2007-12-18 11:49:30',
         first_seen => '2007-12-18 11:48:27'
      },
	  {  checksum   => 'A853B50CDEB4866B3A99CC42AEDCCFCD',
         last_seen  => '2007-10-15 21:45:10',
         first_seen => '2007-10-15 21:45:10'
      },
      {  checksum   => 'AE9D6BB6AF470B997F7D57ACDD8A346E',
         last_seen  => '2009-01-01 00:00:00',
         first_seen => '2009-01-01 00:00:00'
      },
   ],
   'Updates last_seen'
);

$event = {
   arg => "UPDATE foo SET bar='nada' WHERE 1",
   ts  => '081222 13:13:13',
};
my $fp = $qr->fingerprint($event->{arg});
my $checksum = Transformers::make_checksum($fp);
$qv->set_review_info(
   fingerprint => $fp,
   sample      => $event->{arg},
   first_seen  => $event->{ts},
   last_seen   => $event->{ts},
);

$res = $qv->get_review_info($fp);
is_deeply(
   $res,
   {
      checksum_conv => '1C094E0B4F345C8DD3A1C1CD468791EE',
      first_seen    => '2008-12-22 13:13:13',
      last_seen     => '2008-12-22 13:13:13',
      reviewed_by   => undef,
      reviewed_on   => undef,
      comments      => undef,
   },
   'Stores a new event with default values'
);

is_deeply([$qv->review_cols],
   [qw(first_seen last_seen reviewed_by reviewed_on comments)],
   'review columns');

# #############################################################################
# Done.
# #############################################################################
{
   local *STDERR;
   open STDERR, '>', \$output;
   $qv->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
