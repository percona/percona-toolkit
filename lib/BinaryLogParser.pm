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
# BinaryLogParser package
# ###########################################################################
{
# Package: BinaryLogParser
# BinaryLogParser parses binary log files converted to text by mysqlbinlog.
package BinaryLogParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $binlog_line_1 = qr/at (\d+)$/m;
my $binlog_line_2 = qr/^#(\d{6}\s+\d{1,2}:\d\d:\d\d)\s+server\s+id\s+(\d+)\s+end_log_pos\s+(\d+)\s+(?:CRC32\s+0x[a-f0-9]{8}\s+)?(\S+)\s*([^\n]*)$/m;
my $binlog_line_2_rest = qr/thread_id=(\d+)\s+exec_time=(\d+)\s+error_code=(\d+)/m;

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Returns:
#   BinaryLogParser object
sub new {
   my ( $class, %args ) = @_;
   my $self = {
      delim     => undef,
      delim_len => 0,
   };
   return bless $self, $class;
}


# Sub: parse_event
#   Parse binary log events returned by input callback.  This sub implements
#   a standard interface that the *Parser.pm modules share.  Each such
#   module has a sub named "parse_event" that is expected to return one event
#   each time it's called.  Events are received from an input callback,
#   $args{next_event}.  The events are chunks of text that this sub parses
#   into a hashref representing the attributes and values of the event.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   next_event - Coderef that returns the text of the next event from the input
#   tell       - Coderef that tells the file position being read in the input
#
# Optional Arguments:
#   oktorun - Coderef to tell caller that there are no more events
#
# Returns:
#   Hashref representing one event and its attributes and values
sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(next_event tell);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($next_event, $tell) = @args{@required_args};

   local $INPUT_RECORD_SEPARATOR = ";\n#";
   my $pos_in_log = $tell->();
   my $stmt;
   my ($delim, $delim_len) = ($self->{delim}, $self->{delim_len});

   EVENT:
   while ( defined($stmt = $next_event->()) ) {
      my @properties = ('pos_in_log', $pos_in_log);
      my ($ts, $sid, $end, $type, $rest);
      $pos_in_log = $tell->();
      $stmt =~ s/;\n#?\Z//;

      my ( $got_offset, $got_hdr );
      my $pos = 0;
      my $len = length($stmt);
      my $found_arg = 0;
      LINE:
      while ( $stmt =~ m/^(.*)$/mg ) { # /g requires scalar match.
         $pos     = pos($stmt);  # Be careful not to mess this up!
         my $line = $1;          # Necessary for /g and pos() to work.
         $line    =~ s/$delim// if $delim;
         PTDEBUG && _d($line);

         if ( $line =~ m/^\/\*.+\*\/;/ ) {
            PTDEBUG && _d('Comment line');
            next LINE;
         }
 
         if ( $line =~ m/^DELIMITER/m ) {
            my ( $del ) = $line =~ m/^DELIMITER (\S*)$/m;
            if ( $del ) {
               $self->{delim_len} = $delim_len = length $del;
               $self->{delim}     = $delim     = quotemeta $del;
               PTDEBUG && _d('delimiter:', $delim);
            }
            else {
               # Because of the line $stmt =~ s/;\n#?\Z//; above, setting
               # the delimiter back to normal like "DELIMITER ;" appear as
               # "DELIMITER ".
               PTDEBUG && _d('Delimiter reset to ;');
               $self->{delim}     = $delim     = undef;
               $self->{delim_len} = $delim_len = 0;
            }
            next LINE;
         }

         next LINE if $line =~ m/End of log file/;

         # Match the beginning of an event in the binary log.
         if ( !$got_offset && (my ( $offset ) = $line =~ m/$binlog_line_1/m) ) {
            PTDEBUG && _d('Got the at offset line');
            push @properties, 'offset', $offset;
            $got_offset++;
         }

         # Match the 2nd line of binary log header, after "# at OFFSET".
         elsif ( !$got_hdr && $line =~ m/^#(\d{6}\s+\d{1,2}:\d\d:\d\d)/ ) {
            ($ts, $sid, $end, $type, $rest) = $line =~ m/$binlog_line_2/m;
            PTDEBUG && _d('Got the header line; type:', $type, 'rest:', $rest);
            push @properties, 'cmd', 'Query', 'ts', $ts, 'server_id', $sid,
               'end_log_pos', $end;
            $got_hdr++;
         }

         # Handle meta-data lines.
         elsif ( $line =~ m/^(?:#|use |SET)/i ) {

            # Include the current default database given by 'use <db>;'  Again
            # as per the code in sql/log.cc this is case-sensitive.
            if ( my ( $db ) = $line =~ m/^use ([^;]+)/ ) {
               PTDEBUG && _d("Got a default database:", $db);
               push @properties, 'db', $db;
            }

            # Some things you might see in the log output, as printed by
            # sql/log.cc (this time the SET is uppercaes, and again it is
            # case-sensitive).
            # SET timestamp=foo;
            # SET timestamp=foo,insert_id=123;
            # SET insert_id=123;
            elsif ( my ($setting) = $line =~ m/^SET\s+([^;]*)/ ) {
               PTDEBUG && _d("Got some setting:", $setting);
               push @properties, map { s/\s+//; lc } split(/,|\s*=\s*/, $setting);
            }

         }
         else {
            # This isn't a meta-data line.  It's the first line of the
            # whole query. Grab from here to the end of the string and
            # put that into the 'arg' for the event.  Then we are done.
            # Note that if this line really IS the query but we skip in
            # the 'if' above because it looks like meta-data, later
            # we'll remedy that.
            PTDEBUG && _d("Got the query/arg line at pos", $pos);
            $found_arg++;
            if ( $got_offset && $got_hdr ) {
               if ( $type eq 'Xid' ) {
                  my ($xid) = $rest =~ m/(\d+)/;
                  push @properties, 'Xid', $xid;
               }
               elsif ( $type eq 'Query' ) {
                  my ($i, $t, $c) = $rest =~ m/$binlog_line_2_rest/m;
                  push @properties, 'Thread_id', $i, 'Query_time', $t,
                                    'error_code', $c;
               }
               elsif ( $type eq 'Start:' ) {
                  # These are lines like "#090722  7:21:41 server id 12345
                  # end_log_pos 98 Start: binlog v 4, server v 5.0.82-log
                  # created 090722  7:21:41 at startup".  They may or may
                  # not have a statement after them (ROLLBACK can follow
                  # this line), so we do not want to skip these types.
                  PTDEBUG && _d("Binlog start");
               }
               else {
                  PTDEBUG && _d('Unknown event type:', $type);
                  next EVENT;
               }
            }
            else {
               PTDEBUG && _d("It's not a query/arg, it's just some SQL fluff");
               push @properties, 'cmd', 'Query', 'ts', undef;
            }

            # Removing delimiters alters the length of $stmt, so we account
            # for this in our substr() offset.  If $pos is equal to the length
            # of $stmt, then this $line is the whole $arg (i.e. one line
            # query).  In this case, we go back the $delim_len that was
            # removed from this $line.  Otherwise, there are more lines to
            # this arg so a delimiter has not yet been removed (it remains
            # somewhere in $arg, at least at the end).  Therefore, we do not
            # go back any extra.
            my $delim_len = ($pos == length($stmt) ? $delim_len : 0);
            my $arg = substr($stmt, $pos - length($line) - $delim_len);

            $arg =~ s/$delim// if $delim; # Remove the delimiter.

            # Sometimes DELIMITER appears at the end of an arg, so we have
            # to catch it again.  Queries in this arg before this new
            # DELIMITER should have the old delim, which is why we still
            # remove it in the previous line.
            if ( $arg =~ m/^DELIMITER/m ) {
               my ( $del ) = $arg =~ m/^DELIMITER (\S*)$/m;
               if ( $del ) {
                  $self->{delim_len} = $delim_len = length $del;
                  $self->{delim}     = $delim     = quotemeta $del;
                  PTDEBUG && _d('delimiter:', $delim);
               }
               else {
                  PTDEBUG && _d('Delimiter reset to ;');
                  $del       = ';';
                  $self->{delim}     = $delim     = undef;
                  $self->{delim_len} = $delim_len = 0;
               }

               $arg =~ s/^DELIMITER.*$//m;  # Remove DELIMITER from arg.
            }

            $arg =~ s/;$//gm;  # Ensure ending ; are gone.
            $arg =~ s/\s+$//;  # Remove trailing spaces and newlines.

            push @properties, 'arg', $arg, 'bytes', length($arg);
            last LINE;
         }
      } # LINE

      if ( $found_arg ) {
         # Don't dump $event; want to see full dump of all properties, and after
         # it's been cast into a hash, duplicated keys will be gone.
         PTDEBUG && _d('Properties of event:', Dumper(\@properties));
         my $event = { @properties };
         if ( $args{stats} ) {
            $args{stats}->{events_read}++;
            $args{stats}->{events_parsed}++;
         }
         return $event;
      }
      else {
         PTDEBUG && _d('Event had no arg');
      }
   } # EVENT

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
# End BinaryLogParser package
# ###########################################################################
