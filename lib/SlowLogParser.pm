# This program is copyright 2007-2011 Baron Schwartz, 2011 Percona Ireland Ltd.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
# ###########################################################################
# SlowLogParser package
# ###########################################################################
{
# Package: SlowLogParser
# SlowLogParser parses MySQL slow logs.
package SlowLogParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class ) = @_;
   my $self = {
      pending => [],
      last_event_offset => undef,
   };
   return bless $self, $class;
}

my $slow_log_ts_line = qr/^# Time: ([0-9: ]{15})/;
my $slow_log_uh_line = qr/# User\@Host: ([^\[]+|\[[^[]+\]).*?@ (\S*) \[(.*)\]\s*(?:Id:\s*(\d+))?/;
# These can appear in the log file when it's opened -- for example, when someone
# runs FLUSH LOGS or the server starts.
# /usr/sbin/mysqld, Version: 5.0.67-0ubuntu6-log ((Ubuntu)). started with:
# Tcp port: 3306  Unix socket: /var/run/mysqld/mysqld.sock
# Time                 Id Command    Argument
# These lines vary depending on OS and whether it's embedded.
my $slow_log_hd_line = qr{
      ^(?:
      T[cC][pP]\s[pP]ort:\s+\d+ # case differs on windows/unix
      |
      [/A-Z].*mysqld,\sVersion.*(?:started\swith:|embedded\slibrary)
      |
      Time\s+Id\s+Command
      ).*\n
   }xm;

# This method accepts an open slow log filehandle and callback functions.
# It reads events from the filehandle and calls the callbacks with each event.
# It may find more than one event per call.  $misc is some placeholder for the
# future and for compatibility with other query sources.
#
# Each event is a hashref of attribute => value pairs like:
#  my $event = {
#     ts  => '',    # Timestamp
#     id  => '',    # Connection ID
#     arg => '',    # Argument to the command
#     other attributes...
#  };
#
# Returns the number of events it finds.
#
# NOTE: If you change anything inside this subroutine, you need to profile
# the result.  Sometimes a line of code has been changed from an alternate
# form for performance reasons -- sometimes as much as 20x better performance.
sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(next_event tell);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($next_event, $tell) = @args{@required_args};

   # Read a whole stmt at a time.  But, to make things even more fun, sometimes
   # part of the log entry might continue past the separator.  In these cases we
   # peek ahead (see code below.)  We do it this way because in the general
   # case, reading line-by-line is too slow, and the special-case code is
   # acceptable.  And additionally, the line terminator doesn't work for all
   # cases; the header lines might follow a statement, causing the paragraph
   # slurp to grab more than one statement at a time.
   my $pending = $self->{pending};
   local $INPUT_RECORD_SEPARATOR = ";\n#";
   my $trimlen    = length($INPUT_RECORD_SEPARATOR);
   my $pos_in_log = $tell->();
   my $stmt;

   EVENT:
   while (
         defined($stmt = shift @$pending)
      or defined($stmt = $next_event->())
   ) {
      my @properties = ('cmd', 'Query', 'pos_in_log', $pos_in_log);
      $self->{last_event_offset} = $pos_in_log;
      $pos_in_log = $tell->();

      # If there were such lines in the file, we may have slurped > 1 event.
      # Delete the lines and re-split if there were deletes.  This causes the
      # pos_in_log to be inaccurate, but that's really okay.
      if ( $stmt =~ s/$slow_log_hd_line//go ){ # Throw away header lines in log
         my @chunks = split(/$INPUT_RECORD_SEPARATOR/o, $stmt);
         if ( @chunks > 1 ) {
            PTDEBUG && _d("Found multiple chunks");
            $stmt = shift @chunks;
            unshift @$pending, @chunks;
         }
      }

      # There might not be a leading '#' because $INPUT_RECORD_SEPARATOR will
      # have gobbled that up.  And the end may have all/part of the separator.
      $stmt = '#' . $stmt unless $stmt =~ m/\A#/;
      $stmt =~ s/;\n#?\Z//;

      # The beginning of a slow-query-log event should be something like
      # # Time: 071015 21:43:52
      # Or, it might look like this, sometimes at the end of the Time: line:
      # # User@Host: root[root] @ localhost []

      # The following line contains variables intended to be sure we do
      # particular things once and only once, for those regexes that will
      # match only one line per event, so we don't keep trying to re-match
      # regexes.
      my ($got_ts, $got_uh, $got_ac, $got_db, $got_set, $got_embed);
      my $pos = 0;
      my $len = length($stmt);
      my $found_arg = 0;
      LINE:
      while ( $stmt =~ m/^(.*)$/mg ) { # /g is important, requires scalar match.
         $pos     = pos($stmt);  # Be careful not to mess this up!
         my $line = $1;          # Necessary for /g and pos() to work.
         PTDEBUG && _d($line);

         # Handle meta-data lines.  These are case-sensitive.  If they appear in
         # the log with a different case, they are from a user query, not from
         # something printed out by sql/log.cc.
         if ($line =~ m/^(?:#|use |SET (?:last_insert_id|insert_id|timestamp))/o) {

            # Maybe it's the beginning of the slow query log event.  XXX
            # something to know: Perl profiling reports this line as the hot
            # spot for any of the conditions in the whole if/elsif/elsif
            # construct.  So if this line looks "hot" then profile each
            # condition separately.
            if ( !$got_ts && (my ( $time ) = $line =~ m/$slow_log_ts_line/o)) {
               PTDEBUG && _d("Got ts", $time);
               push @properties, 'ts', $time;
               ++$got_ts;
               # The User@Host might be concatenated onto the end of the Time.
               if ( !$got_uh
                  && ( my ( $user, $host, $ip, $thread_id ) = $line =~ m/$slow_log_uh_line/o )
               ) {
                  PTDEBUG && _d("Got user, host, ip", $user, $host, $ip);
                  $host ||= $ip;  # sometimes host is missing when using skip-name-resolve (LP #issue 1262456)
                  push @properties, 'user', $user, 'host', $host, 'ip', $ip;
                  # 5.6 has the thread id on the User@Host line
                  if ( $thread_id ) {  
                     push @properties, 'Thread_id', $thread_id;
                 }
                 ++$got_uh;
               }
            }

            # Maybe it's the user/host line of a slow query log
            # # User@Host: root[root] @ localhost []
            elsif ( !$got_uh
                  && ( my ( $user, $host, $ip, $thread_id ) = $line =~ m/$slow_log_uh_line/o )
            ) {
                  PTDEBUG && _d("Got user, host, ip", $user, $host, $ip);
                  $host ||= $ip;  # sometimes host is missing when using skip-name-resolve (LP #issue 1262456)
                  push @properties, 'user', $user, 'host', $host, 'ip', $ip;
                  # 5.6 has the thread id on the User@Host line
                  if ( $thread_id ) {       
                     push @properties, 'Thread_id', $thread_id;
                 }
               ++$got_uh;
            }

            # A line that looks like meta-data but is not:
            # # administrator command: Quit;
            elsif (!$got_ac && $line =~ m/^# (?:administrator command:.*)$/) {
               PTDEBUG && _d("Got admin command");
               $line =~ s/^#\s+//;  # string leading "# ".
               push @properties, 'cmd', 'Admin', 'arg', $line;
               push @properties, 'bytes', length($properties[-1]);
               ++$found_arg;
               ++$got_ac;
            }

            # Maybe it's the timing line of a slow query log, or another line
            # such as that... they typically look like this:
            # # Query_time: 2  Lock_time: 0  Rows_sent: 1  Rows_examined: 0
            elsif ( $line =~ m/^# +[A-Z][A-Za-z_]+: \S+/ ) { # Make the test cheap!
               PTDEBUG && _d("Got some line with properties");

               # http://code.google.com/p/maatkit/issues/detail?id=1104
               if ( $line =~ m/Schema:\s+\w+: / ) {
                  PTDEBUG && _d('Removing empty Schema attrib');
                  $line =~ s/Schema:\s+//;
                  PTDEBUG && _d($line);
               }

               # I tried using split, but coping with the above bug makes it
               # slower than a complex regex match.
               my @temp = $line =~ m/(\w+):\s+(\S+|\Z)/g;
               push @properties, @temp;
            }

            # Include the current default database given by 'use <db>;'  Again
            # as per the code in sql/log.cc this is case-sensitive.
            elsif ( !$got_db && (my ( $db ) = $line =~ m/^use ([^;]+)/ ) ) {
               PTDEBUG && _d("Got a default database:", $db);
               push @properties, 'db', $db;
               ++$got_db;
            }

            # Some things you might see in the log output, as printed by
            # sql/log.cc (this time the SET is uppercaes, and again it is
            # case-sensitive).
            # SET timestamp=foo;
            # SET timestamp=foo,insert_id=123;
            # SET insert_id=123;
            elsif (!$got_set && (my ($setting) = $line =~ m/^SET\s+([^;]*)/)) {
               # Note: this assumes settings won't be complex things like
               # SQL_MODE, which as of 5.0.51 appears to be true (see sql/log.cc,
               # function MYSQL_LOG::write(THD, char*, uint, time_t)).
               PTDEBUG && _d("Got some setting:", $setting);
               push @properties, split(/,|\s*=\s*/, $setting);
               ++$got_set;
            }

            # Handle pathological special cases. The "# administrator command"
            # is one example: it can come AFTER lines that are not commented,
            # so it looks like it belongs to the next event, and it won't be
            # in $stmt. Profiling shows this is an expensive if() so we do
            # this only if we've seen the user/host line.
            if ( !$found_arg && $pos == $len ) {
               PTDEBUG && _d("Did not find arg, looking for special cases");
               local $INPUT_RECORD_SEPARATOR = ";\n";  # get next line
               if ( defined(my $l = $next_event->()) ) {
                  if ( $l =~ /^\s*[A-Z][a-z_]+: / ) {
                     PTDEBUG && _d("Found NULL query before", $l);
                     # https://bugs.launchpad.net/percona-toolkit/+bug/1082599
                     # This is really pathological but it happens:
                     #   header_for_query_1
                     #   SET timestamp=123;
                     #   use db;
                     #   header_for_query_2
                     # In this case, "get next line" ^ will actually fetch
                     # header_for_query_2 and the first line of any arg data,
                     # so to get the rest of the arg data, we switch back to
                     # the default input rec. sep.
                     local $INPUT_RECORD_SEPARATOR = ";\n#";
                     my $rest_of_event = $next_event->();
                     push @{$self->{pending}}, $l . $rest_of_event;
                     push @properties, 'cmd', 'Query', 'arg', '/* No query */';
                     push @properties, 'bytes', 0;
                     $found_arg++;
                  }
                  else {
                     chomp $l;
                     $l =~ s/^\s+//;
                     PTDEBUG && _d("Found admin statement", $l);
                     push @properties, 'cmd', 'Admin', 'arg', $l;
                     push @properties, 'bytes', length($properties[-1]);
                     $found_arg++;
                  }
               }
               else {
                  # Unrecoverable -- who knows what happened.  This is possible,
                  # for example, if someone does something like "head -c 10000
                  # /path/to/slow.log | mk-log-parser".  Or if there was a
                  # server crash and the file has no newline.
                  PTDEBUG && _d("I can't figure out what to do with this line");
                  next EVENT;
               }
            }
         }
         else {
            # This isn't a meta-data line.  It's the first line of the
            # whole query. Grab from here to the end of the string and
            # put that into the 'arg' for the event.  Then we are done.
            # Note that if this line really IS the query but we skip in
            # the 'if' above because it looks like meta-data, later
            # we'll remedy that.
            PTDEBUG && _d("Got the query/arg line");
            my $arg = substr($stmt, $pos - length($line));
            push @properties, 'arg', $arg, 'bytes', length($arg);
            # Handle embedded attributes.
            if ( $args{misc} && $args{misc}->{embed}
               && ( my ($e) = $arg =~ m/($args{misc}->{embed})/)
            ) {
               push @properties, $e =~ m/$args{misc}->{capture}/g;
            }
            last LINE;
         }
      }

      # Don't dump $event; want to see full dump of all properties, and after
      # it's been cast into a hash, duplicated keys will be gone.
      PTDEBUG && _d('Properties of event:', Dumper(\@properties));
      my $event = { @properties };
      if ( !$event->{arg} ) {
         PTDEBUG && _d('Partial event, no arg');
      }
      else {
         $self->{last_event_offset} = undef;
         if ( $args{stats} ) {
            $args{stats}->{events_read}++;
            $args{stats}->{events_parsed}++;
         }
      }
      return $event;
   } # EVENT

   @$pending = ();
   $args{oktorun}->(0) if $args{oktorun};
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End SlowLogParser package
# ###########################################################################
