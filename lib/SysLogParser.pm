# This program is copyright 2010-2011 Baron Schwartz, 2011 Percona Inc.
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
# SysLogParser package
# ###########################################################################
{
# Package: SysLogParser
# SysLogParser parses events from syslogs.
package SysLogParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# This regex matches the message number, line number, and content of a syslog
# message:
# 2008 Jan  9 16:16:34 hostname postgres[30059]: [13-2] ...content...
my $syslog_regex = qr{\A.*\w+\[\d+\]: \[(\d+)-(\d+)\] (.*)\Z};

# This class generates currying functions that wrap around a standard
# log-parser's next_event() and tell() function pointers.  The wrappers behave
# the same way, except that they'll return entire syslog events, instead of
# lines at a time.  To use it, do the following:
#
# sub parse_event {
#    my ($self, %args) = @_;
#    my ($next_event, $tell, $is_syslog) = SysLogParser::make_closures(%args);
#    # ... write your code to use the $next_event and $tell here...
# }
#
# If the log isn't in syslog format, $is_syslog will be false and you'll get
# back simple wrappers around the $next_event and $tell functions.  (They still
# have to be wrapped, because to find out whether the log is in syslog format,
# the first line has to be examined.)
sub new {
   my ( $class ) = @_;
   my $self = {};
   return bless $self, $class;
}

# This method is here so that SysLogParser can be used and tested in its own
# right.  However, its ability to generate wrapper functions probably means that
# it should be used as a translation layer, not directly.  You can use this code
# as an example of how to integrate this into other packages.
sub parse_event {
   my ( $self, %args ) = @_;
   my ( $next_event, $tell, $is_syslog ) = $self->generate_wrappers(%args);
   return $next_event->();
}

# This is an example of how a class can seamlessly put a syslog translation
# layer underneath itself.
sub generate_wrappers {
   my ( $self, %args ) = @_;

   # Reset everything, just in case some cruft was left over from a previous use
   # of this object.  The object has stateful closures.  If this isn't done,
   # then they'll keep reading from old filehandles.  The sanity check is based
   # on the memory address of the closure!
   if ( ($self->{sanity} || '') ne "$args{next_event}" ){
      PTDEBUG && _d("Clearing and recreating internal state");
      @{$self}{qw(next_event tell is_syslog)} = $self->make_closures(%args);
      $self->{sanity} = "$args{next_event}";
   }

   # Return the wrapper functions!
   return @{$self}{qw(next_event tell is_syslog)};
}

# Make the closures!  The $args{misc}->{new_event_test} is an optional
# subroutine reference, which tells the wrapper when to consider a line part of
# a new event, in syslog format, even when it's technically the same syslog
# event.  See the test for samples/pg-syslog-002.txt for an example.  This
# argument should be passed in via the call to parse_event().  Ditto for
# 'line_filter', which is some processing code to run on every line of content
# in an event.
sub make_closures {
   my ( $self, %args ) = @_;

   # The following variables will be referred to in the manufactured
   # subroutines, making them proper closures.
   my $next_event     = $args{'next_event'};
   my $tell           = $args{'tell'};
   my $new_event_test = $args{'misc'}->{'new_event_test'};
   my $line_filter    = $args{'misc'}->{'line_filter'};

   # The first thing to do is get a line from the log and see if it's from
   # syslog.
   my $test_line = $next_event->();
   PTDEBUG && _d('Read first sample/test line:', $test_line);

   # If it's syslog, we have to generate a moderately elaborate wrapper
   # function.
   if ( defined $test_line && $test_line =~ m/$syslog_regex/o ) {

      # Within syslog-parsing subroutines, we'll use LLSP (low-level syslog
      # parser) as a PTDEBUG line prefix.
      PTDEBUG && _d('This looks like a syslog line, PTDEBUG prefix=LLSP');

      # Grab the interesting bits out of the test line, and save the result.
      my ($msg_nr, $line_nr, $content) = $test_line =~ m/$syslog_regex/o;
      my @pending = ($test_line);
      my $last_msg_nr = $msg_nr;
      my $pos_in_log  = 0;

      # Generate the subroutine for getting a full log message without syslog
      # breaking it across multiple lines.
      my $new_next_event = sub {
         PTDEBUG && _d('LLSP: next_event()');

         # Keeping the pos_in_log variable right is a bit tricky!  In general,
         # we have to tell() the filehandle before trying to read from it,
         # getting the position before the data we've just read.  The simple
         # rule is that when we push something onto @pending, which we almost
         # always do, then $pos_in_log should point to the beginning of that
         # saved content in the file.
         PTDEBUG && _d('LLSP: Current virtual $fh position:', $pos_in_log);
         my $new_pos = 0;

         # @arg_lines is where we store up the content we're about to return.
         # It contains $content; @pending contains a single saved $line.
         my @arg_lines;

         # Here we actually examine lines until we have found a complete event.
         my $line;
         LINE:
         while (
            defined($line = shift @pending)
            || do {
               # Save $new_pos, because when we hit EOF we can't $tell->()
               # anymore.
               eval { $new_pos = -1; $new_pos = $tell->() };
               defined($line = $next_event->());
            }
         ) {
            PTDEBUG && _d('LLSP: Line:', $line);

            # Parse the line.
            ($msg_nr, $line_nr, $content) = $line =~ m/$syslog_regex/o;
            if ( !$msg_nr ) {
               die "Can't parse line: $line";
            }

            # The message number has changed -- thus, new message.
            elsif ( $msg_nr != $last_msg_nr ) {
               PTDEBUG && _d('LLSP: $msg_nr', $last_msg_nr, '=>', $msg_nr);
               $last_msg_nr = $msg_nr;
               last LINE;
            }

            # Or, the caller gave us a custom new_event_test and it is true --
            # thus, also new message.
            elsif ( @arg_lines && $new_event_test && $new_event_test->($content) ) {
               PTDEBUG && _d('LLSP: $new_event_test matches');
               last LINE;
            }

            # Otherwise it's part of the current message; put it onto the list
            # of lines pending.  We have to translate characters that syslog has
            # munged.  Some translate TAB into the literal characters '^I' and
            # some, rsyslog on Debian anyway, seem to translate all whitespace
            # control characters into an octal string representing the character
            # code.
            # Example: #011FROM pg_catalog.pg_class c
            $content =~ s/#(\d{3})/chr(oct($1))/ge;
            $content =~ s/\^I/\t/g;
            if ( $line_filter ) {
               PTDEBUG && _d('LLSP: applying $line_filter');
               $content = $line_filter->($content);
            }

            push @arg_lines, $content;
         }
         PTDEBUG && _d('LLSP: Exited while-loop after finding a complete entry');

         # Mash the pending stuff together to return it.
         my $psql_log_event = @arg_lines ? join('', @arg_lines) : undef;
         PTDEBUG && _d('LLSP: Final log entry:', $psql_log_event);

         # Save the new content into @pending for the next time.  $pos_in_log
         # must also be updated to whatever $new_pos is.
         if ( defined $line ) {
            PTDEBUG && _d('LLSP: Saving $line:', $line);
            @pending = $line;
            PTDEBUG && _d('LLSP: $pos_in_log:', $pos_in_log, '=>', $new_pos);
            $pos_in_log = $new_pos;
         }
         else {
            # We hit the end of the file.
            PTDEBUG && _d('LLSP: EOF reached');
            @pending     = ();
            $last_msg_nr = 0;
         }

         return $psql_log_event;
      };

      # Create the closure for $tell->();
      my $new_tell = sub {
         PTDEBUG && _d('LLSP: tell()', $pos_in_log);
         return $pos_in_log;
      };

      return ($new_next_event, $new_tell, 1);
   }

   # This is either at EOF already, or it's not syslog format.
   else {

      # Within plain-log-parsing subroutines, we'll use PLAIN as a PTDEBUG
      # line prefix.
      PTDEBUG && _d('Plain log, or we are at EOF; PTDEBUG prefix=PLAIN');

      # The @pending array is really only needed to return the one line we
      # already read as a test.  Too bad we can't just push it back onto the
      # log.  TODO: maybe we can test whether the filehandle is seekable and
      # seek back to the start, then just return the unwrapped functions?
      my @pending = defined $test_line ? ($test_line) : ();

      my $new_next_event = sub {
         PTDEBUG && _d('PLAIN: next_event(); @pending:', scalar @pending);
         return @pending ? shift @pending : $next_event->();
      };
      my $new_tell = sub {
         PTDEBUG && _d('PLAIN: tell(); @pending:', scalar @pending);
         return @pending ? 0 : $tell->();
      };
      return ($new_next_event, $new_tell, 0);
   }
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
# End SysLogParser package
# ###########################################################################
