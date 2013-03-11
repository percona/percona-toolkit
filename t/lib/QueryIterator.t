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

use QueryRewriter;
use FileIterator;
use QueryIterator;
use RawLogParser;
use PerconaTest;

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $sample = "$trunk/t/lib/samples/";

my $file_iter = FileIterator->new();
my $parser    = RawLogParser->new();
my $qr        = QueryRewriter->new();
my $query_iter;

sub test_query_iter {
   my (%args) = @_;
   my $file = $args{file};
   my $name = $args{name};

   my @events;
   while ( my $event = $query_iter->next() ) {
      push @events, $event;
   }

   is_deeply(
      \@events,
      $args{expect},
      $args{name}
   ) or diag(Dumper(\@events));
}

my $files = $file_iter->get_file_itr(
   "$sample/rawlogs/rawlog002.txt",
);

$query_iter = QueryIterator->new(
   file_iter   => $files,
   parser      => sub { return $parser->parse_event(@_) },
   fingerprint => sub { return $qr->fingerprint(@_) },
   oktorun     => sub { return 1 },
   read_only   => 1,
);

test_query_iter(
   name   => "rawlog002.txt read-only",
   expect => [
      {  pos_in_log  => 0,
         arg         => 'SELECT c FROM t WHERE id=1',
         bytes       => 26,
         cmd         => 'Query',
         Query_time  => 0,
         fingerprint => 'select c from t where id=?',
      },
      {  pos_in_log  => 27,
         arg         => '/* Hello, world! */ SELECT * FROM t2 LIMIT 1',
         bytes       => 44,
         cmd         => 'Query',
         Query_time  => 0,
         fingerprint => 'select * from t? limit ?',
      }

   ],
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
