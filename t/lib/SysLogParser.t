#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 26;

use SysLogParser;
use PerconaTest;

my $p = SysLogParser->new;

# The final line is broken across two lines in the actual log, but it's one
# logical event.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-syslog-005.txt',
   result => [
      '2010-02-10 09:03:26.918 EST c=4b72bcae.d01,u=[unknown],D=[unknown] LOG:  connection received: host=[local]',
      '2010-02-10 09:03:26.922 EST c=4b72bcae.d01,u=fred,D=fred LOG:  connection authorized: user=fred database=fred',
      '2010-02-10 09:03:36.645 EST c=4b72bcae.d01,u=fred,D=fred LOG:  duration: 0.627 ms  statement: select 1;',
      '2010-02-10 09:03:39.075 EST c=4b72bcae.d01,u=fred,D=fred LOG:  disconnection: session time: 0:00:12.159 user=fred database=fred host=[local]',
   ],
);

# This test case examines $tell and sees whether it's correct or not.  It also
# tests whether we can correctly pass in a callback that lets the caller
# override the rules about when a new event is seen.  In this example, we want
# to break the last event up into two parts, even though they are the same event
# in the syslog entry.
{
   my $file = "$trunk/t/lib/samples/pg/pg-syslog-002.txt";
   eval {
      open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
      my %parser_args = (
         next_event => sub { return <$fh>; },
         tell       => sub { return tell($fh);  },
         fh         => $fh,
         misc       => {
            new_event_test => sub {
               # A simplified PgLogParser::$log_line_regex
               defined $_[0] && $_[0] =~ m/STATEMENT/;
            },
         }
      );
      my ( $next_event, $tell, $is_syslog )
         = $p->generate_wrappers(%parser_args);

      is ($tell->(),
         0,
         'pg-syslog-002.txt $tell 0 ok');
      is ($next_event->(),
         '2010-02-08 09:52:41.526 EST c=4b701056.1dc6,u=fred,D=fred LOG: '
         . ' statement: select * from pg_stat_bgwriter;',
         'pg-syslog-002.txt $next_event 0 ok');

      is ($tell->(),
         153,
         'pg-syslog-002.txt $tell 1 ok');
      is ($next_event->(),
         '2010-02-08 09:52:41.533 EST c=4b701056.1dc6,u=fred,D=fred LOG:  '
         . 'duration: 8.309 ms',
         'pg-syslog-002.txt $next_event 1 ok');

      is ($tell->(),
         282,
         'pg-syslog-002.txt $tell 2 ok');
      is ($next_event->(),
         '2010-02-08 09:52:57.807 EST c=4b701056.1dc6,u=fred,D=fred LOG:  '
         . 'statement: create index ix_a on foo (a);',
         'pg-syslog-002.txt $next_event 2 ok');

      is ($tell->(),
         433,
         'pg-syslog-002.txt $tell 3 ok');
      is ($next_event->(),
         '2010-02-08 09:52:57.864 EST c=4b701056.1dc6,u=fred,D=fred ERROR:  '
         . 'relation "ix_a" already exists',
         'pg-syslog-002.txt $next_event 3 ok');

      is ($tell->(),
         576,
         'pg-syslog-002.txt $tell 4 ok');
      is ($next_event->(),
         '2010-02-08 09:52:57.864 EST c=4b701056.1dc6,u=fred,D=fred STATEMENT:  '
         . 'create index ix_a on foo (a);',
         'pg-syslog-002.txt $next_event 4 ok');

      close $fh;
   };
   is(
      $EVAL_ERROR,
      '',
      "No error on samples/pg/pg-syslog-002.txt",
   );

}

# This test case checks a $line_filter, and sees whether lines get proper
# newline-munging.
{
   my $file = "$trunk/t/lib/samples/pg/pg-syslog-003.txt";
   eval {
      open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
      my %parser_args = (
         next_event => sub { return <$fh>; },
         tell       => sub { return tell($fh);  },
         fh         => $fh,
         misc       => {
            line_filter => sub {
               # A simplified PgLogParser::$log_line_regex
               defined $_[0] && $_[0] =~ s/\A\t/\n/; $_[0];
            },
         }
      );
      my ( $next_event, $tell, $is_syslog )
         = $p->generate_wrappers(%parser_args);

      is ($tell->(),
         0,
         'pg-syslog-003.txt $tell 0 ok');
      is ($next_event->(),
         "2010-02-08 09:53:51.724 EST c=4b701056.1dc6,u=fred,D=fred LOG:  "
          . "statement: SELECT n.nspname as \"Schema\","
          . "\n  c.relname as \"Name\","
          . "\n  CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'i' THEN 'index' WHEN 'S' THEN 'sequence' WHEN 's' THEN"
          . " 'special' END as \"Type\","
          . "\n  r.rolname as \"Owner\""
          . "\nFROM pg_catalog.pg_class c"
          . "\n     JOIN pg_catalog.pg_roles r ON r.oid = c.relowner"
          . "\n     LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace"
          . "\nWHERE c.relkind IN ('r','v','S','')"
          . "\n  AND n.nspname <> 'pg_catalog'"
          . "\n  AND n.nspname !~ '^pg_toast'"
          . "\n  AND pg_catalog.pg_table_is_visible(c.oid)"
          . "\nORDER BY 1,2;",
         'pg-syslog-003.txt $next_event 0 ok');

      close $fh;
   };
   is(
      $EVAL_ERROR,
      '',
      "No error on samples/pg/pg-syslog-003.txt",
   );

}

# This test case checks pos_in_log again, without any filters.
{
   my $file = "$trunk/t/lib/samples/pg/pg-syslog-005.txt";
   eval {
      open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
      my %parser_args = (
         next_event => sub { return <$fh>; },
         tell       => sub { return tell($fh);  },
         fh         => $fh,
      );
      my ( $next_event, $tell, $is_syslog )
         = $p->generate_wrappers(%parser_args);

      my @pairs = (
         [0,   '2010-02-10 09:03:26.918 EST c=4b72bcae.d01,u=[unknown],D=[unknown] LOG:  connection received: host=[local]'],
         [152, '2010-02-10 09:03:26.922 EST c=4b72bcae.d01,u=fred,D=fred LOG:  connection authorized: user=fred database=fred'],
         [307, '2010-02-10 09:03:36.645 EST c=4b72bcae.d01,u=fred,D=fred LOG:  duration: 0.627 ms  statement: select 1;'],
         [456, '2010-02-10 09:03:39.075 EST c=4b72bcae.d01,u=fred,D=fred LOG:  disconnection: session time: 0:00:12.159 user=fred database=fred host=[local]'],
      );

      foreach my $i ( 0 .. $#pairs) {
         my $pair = $pairs[$i];
         is ($tell->(), $pair->[0], "pg-syslog-005.txt \$tell $i ok");
         is ($next_event->(), $pair->[1], "pg-syslog-005.txt \$next_event $i ok");
      }

      close $fh;
   };
   is(
      $EVAL_ERROR,
      '',
      "No error on samples/pg/pg-syslog-005.txt",
   );

}

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $p->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
