# This program is copyright 2010-2011 Baron Schwartz, 2011 Percona Ireland Ltd.
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
# PgLogParser package
# ###########################################################################
{
# Package: PgLogParser
# PgLogParser parses Postgres logs.
package PgLogParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# This regex is partially inspired by one from pgfouine.  But there is no
# documentation on the last capture in that regex, so I omit that.  (TODO: that
# actually seems to be for CSV logging.)
#     (?:[0-9XPFDBLA]{2}[0-9A-Z]{3}:[\s]+)?
# Here I constrain to match at least two spaces after the severity level,
# because the source code tells me to.  I believe this is controlled in elog.c:
# appendStringInfo(&buf, "%s:  ", error_severity(edata->elevel));
my $log_line_regex = qr{
   (LOG|DEBUG|CONTEXT|WARNING|ERROR|FATAL|PANIC|HINT
    |DETAIL|NOTICE|STATEMENT|INFO|LOCATION)
   :\s\s+
   }x;

# The following are taken right from the comments in postgresql.conf for
# log_line_prefix.
my %attrib_name_for = (
   u => 'user',
   d => 'db',
   r => 'host', # With port
   h => 'host',
   p => 'Process_id',
   t => 'ts',
   m => 'ts',   # With milliseconds
   i => 'Query_type',
   c => 'Session_id',
   l => 'Line_no',
   s => 'Session_id',
   v => 'Vrt_trx_id',
   x => 'Trx_id',
);

# This class's data structure is a hashref with some statefulness: pending
# lines.  This is necessary because we sometimes don't know whether the event is
# complete until we read the next line or even several lines, so we store these.
#
# Another bit of data that's stored in $self is some code to automatically
# translate syslog into plain log format.
sub new {
   my ( $class ) = @_;
   my $self = {
      pending    => [],
      is_syslog  => undef,
      next_event => undef,
      'tell'     => undef,
   };
   return bless $self, $class;
}

# This method accepts an iterator that contains an open log filehandle.  It
# reads events from the filehandle by calling the iterator, and returns the
# events.
#
# Each event is a hashref of attribute => value pairs like:
#  my $event = {
#     ts  => '',    # Timestamp
#     arg => '',    # Argument to the command
#     other attributes...
#  };
#
# The log format is ideally prefixed with the following:
#
#  * timestamp with microseconds
#  * session ID, user, database
#
# The format I'd like to see is something like this:
#
# 2010-02-08 15:31:48.685 EST c=4b7074b4.985,u=user,D=database LOG:
#
# However, pgfouine supports user=user, db=database format.  And I think
# it should be reasonable to grab pretty much any name=value properties out, and
# handle them based on the lower-cased first character of $name, to match the
# special values that are possible to give for log_line_prefix. For example, %u
# = user, so anything starting with a 'u' should be interpreted as a user.
#
# In general the log format is rather flexible, and we don't know by looking at
# any given line whether it's the last line in the event.  So we often have to
# read a line and then decide what to do with the previous line we saw.  Thus we
# use 'pending' when necessary but we try to do it as little as possible,
# because it's double work to defer and re-parse lines; and we try to defer as
# soon as possible so we don't have to do as much work.
#
# There are 3 categories of lines in a log file, referred to in the code as case
# 1/2/3:
#
# - Those that start a possibly multi-line event
# - Those that can continue one
# - Those that are neither the start nor the continuation, and thus must be the
#   end.
#
# In cases 1 and 3, we have to check whether information from previous lines has
# been accumulated.  If it has, we defer the current line and create the event.
# Otherwise we keep going, looking for more lines for the event that begins with
# the current line.  Processing the lines is easiest if we arrange the cases in
# this order: 2, 1, 3.
#
# The term "line" is to be interpreted loosely here.  Logs that are in syslog
# format might have multi-line "lines" that are handled by the generated
# $next_event closure and given back to the main while-loop with newlines in
# them.  Therefore, regexes that match "the rest of the line" generally need the
# /s flag.
sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(next_event tell);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   # The subroutine references that wrap the filehandle operations.
   my ( $next_event, $tell, $is_syslog ) = $self->generate_wrappers(%args);

   # These are the properties for the log event, which will later be used to
   # create an event hash ref.
   my @properties = ();

   # Holds the current line being processed, and its position in the log as a
   # byte offset from the beginning.  In some cases we'll have to reset this
   # position later.  We'll also have to take a wait-and-see attitude towards
   # the $pos_in_log, so we use $new_pos to record where we're working in the
   # log, and $pos_in_log to record where the beginning of the current event
   # started.
   my ($pos_in_log, $line, $was_pending) = $self->get_line();
   my $new_pos;

   # Sometimes we need to accumulate some lines and then join them together.
   # This is used for that.
   my @arg_lines;

   # This is used to signal that an entire event has been found, and thus exit
   # the while loop.
   my $done;

   # This is used to signal that an event's duration has already been found.
   # See the sample file pg-syslog-001.txt and the test for it.
   my $got_duration;

   # Before we start, we read and discard lines until we get one with a header.
   # The only thing we can really count on is that a header line should have
   # the header in it.  But, we only do this if we aren't in the middle of an
   # ongoing event, whose first line was pending.
   if ( !$was_pending && (!defined $line || $line !~ m/$log_line_regex/o) ) {
      PTDEBUG && _d('Skipping lines until I find a header');
      my $found_header;
      LINE:
      while (
         eval {
            ($new_pos, $line) = $self->get_line();
            defined $line;
         }
      ) {
         if ( $line =~ m/$log_line_regex/o ) {
            $pos_in_log = $new_pos;
            last LINE;
         }
         else {
            PTDEBUG && _d('Line was not a header, will fetch another');
         }
      }
      PTDEBUG && _d('Found a header line, now at pos_in_line', $pos_in_log);
   }

   # We need to keep the line that begins the event we're parsing.
   my $first_line;

   # This is for holding the type of the log line, which is important for
   # choosing the right code to run.
   my $line_type;

   # Parse each line.
   LINE:
   while ( !$done && defined $line ) {

      # Throw away the newline ending.
      chomp $line unless $is_syslog;

      # This while loop works with LOG lines.  Other lines, such as ERROR and
      # so forth, need to be handled outside this loop.  The exception is when
      # there's nothing in progress in @arg_lines, and the non-LOG line might
      # just be something we can get relevant info from.
      if ( (($line_type) = $line =~ m/$log_line_regex/o) && $line_type ne 'LOG' ) {

         # There's something in progress, so we abort the loop and let it be
         # handled specially.
         if ( @arg_lines ) {
            PTDEBUG && _d('Found a non-LOG line, exiting loop');
            last LINE;
         }

         # There's nothing in @arg_lines, so we save what info we can and keep
         # on going.
         else {
            $first_line ||= $line;

            # Handle ERROR and STATEMENT lines...
            if ( my ($e) = $line =~ m/ERROR:\s+(\S.*)\Z/s ) {
               push @properties, 'Error_msg', $e;
               PTDEBUG && _d('Found an error msg, saving and continuing');
               ($new_pos, $line) = $self->get_line();
               next LINE;
            }

            elsif ( my ($s) = $line =~ m/STATEMENT:\s+(\S.*)\Z/s ) {
               push @properties, 'arg', $s, 'cmd', 'Query';
               PTDEBUG && _d('Found a statement, finishing up event');
               $done = 1;
               last LINE;
            }

            else {
               PTDEBUG && _d("I don't know what to do with this line");
            }
         }

      }

      # The log isn't just queries.  It also has status and informational lines
      # in it.  We ignore these, but if we see one that's not recognized, we
      # warn.  These types of things are better off in mk-error-log.
      if (
         $line =~ m{
            Address\sfamily\snot\ssupported\sby\sprotocol
            |archived\stransaction\slog\sfile
            |autovacuum:\sprocessing\sdatabase
            |checkpoint\srecord\sis\sat
            |checkpoints\sare\soccurring\stoo\sfrequently\s\(
            |could\snot\sreceive\sdata\sfrom\sclient
            |database\ssystem\sis\sready
            |database\ssystem\sis\sshut\sdown
            |database\ssystem\swas\sshut\sdown
            |incomplete\sstartup\spacket
            |invalid\slength\sof\sstartup\spacket
            |next\sMultiXactId:
            |next\stransaction\sID:
            |received\ssmart\sshutdown\srequest
            |recycled\stransaction\slog\sfile
            |redo\srecord\sis\sat
            |removing\sfile\s"
            |removing\stransaction\slog\sfile\s"
            |shutting\sdown
            |transaction\sID\swrap\slimit\sis
         }x
      ) {
         # We get the next line to process and skip the rest of the loop.
         PTDEBUG && _d('Skipping this line because it matches skip-pattern');
         ($new_pos, $line) = $self->get_line();
         next LINE;
      }

      # Possibly reset $first_line, depending on whether it was determined to be
      # junk and unset.
      $first_line ||= $line;

      # Case 2: non-header lines, optionally starting with a TAB, are a
      # continuation of the previous line.
      if ( $line !~ m/$log_line_regex/o && @arg_lines ) {

         if ( !$is_syslog ) {
            # We need to translate tabs to newlines.  Weirdly, some logs (see
            # samples/pg-log-005.txt) have newlines without a leading tab.
            # Maybe it's an older log format.
            $line =~ s/\A\t?/\n/;
         }

         # Save the remainder.
         push @arg_lines, $line;
         PTDEBUG && _d('This was a continuation line');
      }

      # Cases 1 and 3: These lines start with some optional meta-data, and then
      # the $log_line_regex followed by the line's log message.  The message can be
      # of the form "label: text....".  Examples:
      # LOG:  duration: 1.565 ms
      # LOG:  statement: SELECT ....
      # LOG:  duration: 1.565 ms  statement: SELECT ....
      # In the above examples, the $label is duration, statement, and duration.
      elsif (
         my ( $sev, $label, $rest )
            = $line =~ m/$log_line_regex(.+?):\s+(.*)\Z/so
      ) {
         PTDEBUG && _d('Line is case 1 or case 3');

         # This is either a case 1 or case 3.  If there's previously gathered
         # data in @arg_lines, it doesn't matter which -- we have to create an
         # event (a Query event), and we're $done.  This is case 0xdeadbeef.
         if ( @arg_lines ) {
            $done = 1;
            PTDEBUG && _d('There are saved @arg_lines, we are done');

            # We shouldn't modify @properties based on $line, because $line
            # doesn't have anything to do with the stuff in @properties, which
            # is all related to the previous line(s).  However, there is one
            # case in which the line could be part of the event: when it's a
            # plain 'duration' line.  This happens when the statement is logged
            # on one line, and then the duration is logged afterwards.  If this
            # is true, then we alter @properties, and we do NOT defer the current
            # line.
            if ( $label eq 'duration' && $rest =~ m/[0-9.]+\s+\S+\Z/ ) {
               if ( $got_duration ) {
                  # Just discard the line.
                  PTDEBUG && _d('Discarding line, duration already found');
               }
               else {
                  push @properties, 'Query_time', $self->duration_to_secs($rest);
                  PTDEBUG && _d("Line's duration is for previous event:", $rest);
               }
            }
            else {
               # We'll come back to this line later.
               $self->pending($new_pos, $line);
               PTDEBUG && _d('Deferred line');
            }
         }

         # Here we test for case 1, lines that can start a multi-line event.
         elsif ( $label =~ m/\A(?:duration|statement|query)\Z/ ) {
            PTDEBUG && _d('Case 1: start a multi-line event');

            # If it's a duration, then there might be a statement later on the
            # same line and the duration applies to that.
            if ( $label eq 'duration' ) {

               if (
                  (my ($dur, $stmt)
                     = $rest =~ m/([0-9.]+ \S+)\s+(?:statement|query): *(.*)\Z/s)
               ) {
                  # It does, so we'll pull out the Query_time etc now, rather
                  # than doing it later, when we might end up in the case above
                  # (case 0xdeadbeef).
                  push @properties, 'Query_time', $self->duration_to_secs($dur);
                  $got_duration = 1;
                  push @arg_lines, $stmt;
                  PTDEBUG && _d('Duration + statement');
               }

               else {
                  # The duration line is just junk.  It's the line after a
                  # statement, but we never saw the statement (else we'd have
                  # fallen into 0xdeadbeef above).  Discard this line and adjust
                  # pos_in_log.  See t/samples/pg-log-002.txt for an example.
                  $first_line = undef;
                  ($pos_in_log, $line) = $self->get_line();
                  PTDEBUG && _d('Line applies to event we never saw, discarding');
                  next LINE;
               }
            }
            else {
               # This isn't a duration line, it's a statement or query.  Put it
               # onto @arg_lines for later and keep going.
               push @arg_lines, $rest;
               PTDEBUG && _d('Putting onto @arg_lines');
            }
         }

         # Here is case 3, lines that can't be in case 1 or 2.  These surely
         # terminate any event that's been accumulated, and if there isn't any
         # such, then we just create an event without the overhead of deferring.
         else {
            $done = 1;
            PTDEBUG && _d('Line is case 3, event is done');

            # Again, if there's previously gathered data in @arg_lines, we have
            # to defer the current line (not touching @properties) and revisit it.
            if ( @arg_lines ) {
               $self->pending($new_pos, $line);
               PTDEBUG && _d('There was @arg_lines, putting line to pending');
            }

            # Otherwise we can parse the line and put it into @properties.
            else {
               PTDEBUG && _d('No need to defer, process event from this line now');
               push @properties, 'cmd', 'Admin', 'arg', $label;

               # For some kinds of log lines, we can grab extra meta-data out of
               # the end of the line.
               # LOG:  connection received: host=[local]
               if ( $label =~ m/\A(?:dis)?connection(?: received| authorized)?\Z/ ) {
                  push @properties, $self->get_meta($rest);
               }

               else {
                  die "I don't understand line $line";
               }

            }
         }

      }

      # If the line isn't case 1, 2, or 3 I don't know what it is.
      else {
         die "I don't understand line $line";
      }

      # We get the next line to process.
      if ( !$done ) {
         ($new_pos, $line) = $self->get_line();
      }
   } # LINE

   # If we're at the end of the file, we finish and tell the caller we're done.
   if ( !defined $line ) {
      PTDEBUG && _d('Line not defined, at EOF; calling oktorun(0) if exists');
      $args{oktorun}->(0) if $args{oktorun};
      if ( !@arg_lines ) {
         PTDEBUG && _d('No saved @arg_lines either, we are all done');
         return undef;
      }
   }

   # If we got kicked out of the while loop because of a non-LOG line, we handle
   # that line here.
   if ( $line_type && $line_type ne 'LOG' ) {
      PTDEBUG && _d('Line is not a LOG line');

      # ERROR lines come in a few flavors.  See t/samples/pg-log-006.txt,
      # t/samples/pg-syslog-002.txt, and t/samples/pg-syslog-007.txt for some
      # examples.  The rules seem to be this: if the ERROR is followed by a
      # STATEMENT, and the STATEMENT's statement matches the query in
      # @arg_lines, then the STATEMENT message is redundant.  (This can be
      # caused by various combos of configuration options in postgresql.conf).
      # However, if the ERROR's STATEMENT line doesn't match what's in
      # @arg_lines, then the ERROR actually starts a new event.  If the ERROR is
      # followed by another LOG event, then the ERROR also starts a new event.
      if ( $line_type eq 'ERROR' ) {
         PTDEBUG && _d('Line is ERROR');

         # If there's already a statement in processing, then put aside the
         # current line, and peek ahead.
         if ( @arg_lines ) {
            PTDEBUG && _d('There is @arg_lines, will peek ahead one line');
            my ( $temp_pos, $temp_line ) = $self->get_line();
            my ( $type, $msg );
            if (
               defined $temp_line
               && ( ($type, $msg) = $temp_line =~ m/$log_line_regex(.*)/o )
               && ( $type ne 'STATEMENT' || $msg eq $arg_lines[-1] )
            ) {
               # Looks like the whole thing is pertaining to the current event
               # in progress.  Add the error message to the event.
               PTDEBUG && _d('Error/statement line pertain to current event');
               push @properties, 'Error_msg', $line =~ m/ERROR:\s*(\S.*)\Z/s;
               if ( $type ne 'STATEMENT' ) {
                  PTDEBUG && _d('Must save peeked line, it is a', $type);
                  $self->pending($temp_pos, $temp_line);
               }
            }
            elsif ( defined $temp_line && defined $type ) {
               # Looks like the current and next line are about a new event.
               # Put them into pending.
               PTDEBUG && _d('Error/statement line are a new event');
               $self->pending($new_pos, $line);
               $self->pending($temp_pos, $temp_line);
            }
            else {
               PTDEBUG && _d("Unknown line", $line);
            }
         }
      }
      else {
         PTDEBUG && _d("Unknown line", $line);
      }
   }

   # If $done is true, then some of the above code decided that the full
   # event has been found.  If we reached the end of the file, then we might
   # also have something in @arg_lines, although we didn't find the "line after"
   # that signals the event was done.  In either case we return an event.  This
   # should be the only 'return' statement in this block of code.
   if ( $done || @arg_lines ) {
      PTDEBUG && _d('Making event');

      # Finish building the event.
      push @properties, 'pos_in_log', $pos_in_log;

      # Statement/query lines will be in @arg_lines.
      if ( @arg_lines ) {
         PTDEBUG && _d('Assembling @arg_lines: ', scalar @arg_lines);
         push @properties, 'arg', join('', @arg_lines), 'cmd', 'Query';
      }

      if ( $first_line ) {
         # Handle some meta-data: a timestamp, with optional milliseconds.
         if ( my ($ts) = $first_line =~ m/([0-9-]{10} [0-9:.]{8,12})/ ) {
            PTDEBUG && _d('Getting timestamp', $ts);
            push @properties, 'ts', $ts;
         }

         # Find meta-data embedded in the log line prefix, in name=value format.
         if ( my ($meta) = $first_line =~ m/(.*?)[A-Z]{3,}:  / ) {
            PTDEBUG && _d('Found a meta-data chunk:', $meta);
            push @properties, $self->get_meta($meta);
         }
      }

      # Dump info about what we've found, but don't dump $event; want to see
      # full dump of all properties, and after it's been cast into a hash,
      # duplicated keys will be gone.
      PTDEBUG && _d('Properties of event:', Dumper(\@properties));
      my $event = { @properties };
      $event->{bytes} = length($event->{arg} || '');
      return $event;
   }

}

# Parses key=value meta-data from the $meta string, and returns a list of event
# attribute names and values.
sub get_meta {
   my ( $self, $meta ) = @_;
   my @properties;
   foreach my $set ( $meta =~ m/(\w+=[^, ]+)/g ) {
      my ($key, $val) = split(/=/, $set);
      if ( $key && $val ) {
         # The first letter of the name, lowercased, determines the
         # meaning of the item.
         if ( my $prop = $attrib_name_for{lc substr($key, 0, 1)} ) {
            push @properties, $prop, $val;
         }
         else {
            PTDEBUG && _d('Bad meta key', $set);
         }
      }
      else {
         PTDEBUG && _d("Can't figure out meta from", $set);
      }
   }
   return @properties;
}

# This subroutine abstracts the process and source of getting a line of text and
# its position in the log file.  It might get the line of text from the log; it
# might get it from the @pending array.  It also does infinite loop checking
# TODO.
sub get_line {
   my ( $self ) = @_;
   my ($pos, $line, $was_pending) = $self->pending;
   if ( ! defined $line ) {
      PTDEBUG && _d('Got nothing from pending, trying the $fh');
      my ( $next_event, $tell) = @{$self}{qw(next_event tell)};
      eval {
         $pos  = $tell->();
         $line = $next_event->();
      };
      if ( PTDEBUG && $EVAL_ERROR ) {
         _d($EVAL_ERROR);
      }
   }

   PTDEBUG && _d('Got pos/line:', $pos, $line);
   return ($pos, $line);
}

# This subroutine defers and retrieves a line/pos pair.  If you give it an
# argument it'll set the stored value.  If not, it'll get one if there is one
# and return it.
sub pending {
   my ( $self, $val, $pos_in_log ) = @_;
   my $was_pending;
   PTDEBUG && _d('In sub pending, val:', $val);
   if ( $val ) {
      push @{$self->{pending}}, [$val, $pos_in_log];
   }
   elsif ( @{$self->{pending}} ) {
      ($val, $pos_in_log) = @{ shift @{$self->{pending}} };
      $was_pending = 1;
   }
   PTDEBUG && _d('Return from pending:', $val, $pos_in_log);
   return ($val, $pos_in_log, $was_pending);
}

# This subroutine manufactures subroutines to automatically translate incoming
# syslog format into standard log format, to keep the main parse_event free from
# having to think about that.  For documentation on how this works, see
# SysLogParser.pm.
sub generate_wrappers {
   my ( $self, %args ) = @_;

   # Reset everything, just in case some cruft was left over from a previous use
   # of this object.  The object has stateful closures.  If this isn't done,
   # then they'll keep reading from old filehandles.  The sanity check is based
   # on the memory address of the closure!
   if ( ($self->{sanity} || '') ne "$args{next_event}" ){
      PTDEBUG && _d("Clearing and recreating internal state");
      eval { require SysLogParser; }; # Required for tests to work.
      my $sl = new SysLogParser();

      # We need a special item in %args for syslog parsing.  (This might not be
      # a syslog log file...)  See the test for t/samples/pg-syslog-002.txt for
      # an example of when this is needed.
      $args{misc}->{new_event_test} = sub {
         my ( $content ) = @_;
         return unless defined $content;
         return $content =~ m/$log_line_regex/o;
      };

      # The TAB at the beginning of the line indicates that there's a newline
      # at the end of the previous line.
      $args{misc}->{line_filter} = sub {
         my ( $content ) = @_;
         $content =~ s/\A\t/\n/;
         return $content;
      };

      @{$self}{qw(next_event tell is_syslog)} = $sl->make_closures(%args);
      $self->{sanity} = "$args{next_event}";
   }

   # Return the wrapper functions!
   return @{$self}{qw(next_event tell is_syslog)};
}

# This subroutine converts various formats to seconds.  Examples:
# 10.870 ms
sub duration_to_secs {
   my ( $self, $str ) = @_;
   PTDEBUG && _d('Duration:', $str);
   my ( $num, $suf ) = split(/\s+/, $str);
   my $factor = $suf eq 'ms'  ? 1000
              : $suf eq 'sec' ? 1
              :                 die("Unknown suffix '$suf'");
   return $num / $factor;
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
# End PgLogParser package
# ###########################################################################
