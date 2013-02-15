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

use FileIterator;
use QueryRewriter;
use QueryIterator;
use SlowLogParser;
use PerconaTest;

my $parser    = SlowLogParser->new();
my $qr        = QueryRewriter->new();
my $file_iter = FileIterator->new();

my $oktorun = 1;
my $sample  = "t/lib/samples/slowlogs";

sub test_query_iter {
   my (%args) = @_;

   my $files = $file_iter->get_file_itr(
      @{$args{files}}
   );

   my $query_iter = QueryIterator->new(
      file_iter   => $files,
      parser      => $args{parser} || $parser,
      fingerprint => sub { return $qr->fingerprint(@_) },
      oktorun     => sub { return $oktorun },
      # Optional args
      default_database => $args{default_database},
      ($args{filter}       ? (filter       => $args{filter})       : ()),
      ($args{read_only}    ? (read_only    => $args{read_only})    : ()),
      ($args{read_timeout} ? (read_timeout => $args{read_timeout}) : ()),
   );

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

my $slow001_events = [
   {
      Lock_time => '0',
      Query_time => '2',
      Rows_examined => '0',
      Rows_sent => '1',
      arg => 'select sleep(2) from n',
      bytes => 22,
      cmd => 'Query',
      db => 'test',
      fingerprint => 'select sleep(?) from n',
      host => 'localhost',
      ip => '',
      pos_in_log => 0,
      ts => '071015 21:43:52',
      user => 'root',
   },
   {
      Lock_time => '0',
      Query_time => '2',
      Rows_examined => '0',
      Rows_sent => '1',
      arg => 'select sleep(2) from test.n',
      bytes => 27,
      cmd => 'Query',
      db => 'sakila',
      fingerprint => 'select sleep(?) from test.n',
      host => 'localhost',
      ip => '',
      pos_in_log => 359,
      ts => '071015 21:45:10',
      user => 'root',
   }
];

test_query_iter(
   name   => "slow001.txt, defaults",
   files  => [
      "$trunk/$sample/slow001.txt"     
   ],
   expect => $slow001_events,
);

test_query_iter(
   name         => "slow001.txt, read_timeout=5",
   read_timeout => 5,
   files        => [
      "$trunk/$sample/slow001.txt"     
   ],
   expect => $slow001_events,
);

test_query_iter(
   name      => "slow001.txt, read_only",
   read_only => 1,
   files     => [
      "$trunk/$sample/slow001.txt"     
   ],
   expect => $slow001_events,
);

test_query_iter(
   name   => "slow001.txt, in-line filter",
   filter => '$event->{db} eq "test"',
   files  => [
      "$trunk/$sample/slow001.txt"     
   ],
   expect => [ $slow001_events->[0] ],
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
