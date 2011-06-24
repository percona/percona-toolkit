# This program is copyright 2009-2011 Percona Inc.
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
# HTTPProtocolParser package $Revision: 5811 $
# ###########################################################################

# Package: HTTPProtocolParser
# HTTPProtocolParser parses HTTP traffic from tcpdump files.
{
package HTTPProtocolParser;
use base 'ProtocolParser';

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# server is the "host:port" of the sever being watched.  It's auto-guessed if
# not specified.
sub new {
   my ( $class, %args ) = @_;
   my $self = $class->SUPER::new(
      %args,
      port => 80,
   );
   return $self;
}

# Handles a packet from the server given the state of the session.  Returns an
# event if one was ready to be created, otherwise returns nothing.
sub _packet_from_server {
   my ( $self, $packet, $session, $misc ) = @_;
   die "I need a packet"  unless $packet;
   die "I need a session" unless $session;

   MKDEBUG && _d('Packet is from server; client state:', $session->{state}); 

   # If there's no session state, then we're catching a server response
   # mid-stream.
   if ( !$session->{state} ) {
      MKDEBUG && _d('Ignoring mid-stream server response');
      return;
   }

   if ( $session->{out_of_order} ) {
      # We're waiting for the header so we can get the content length.
      # Once we know this, we can determine how many out of order packets
      # we need to complete the request, then order them and re-process.
      my ($line1, $content);
      if ( !$session->{have_header} ) {
         ($line1, $content) = $self->_parse_header(
            $session, $packet->{data}, $packet->{data_len});
      }
      if ( $line1 ) {
         $session->{have_header} = 1;
         $packet->{content_len}  = length $content;
         MKDEBUG && _d('Got out of order header with',
            $packet->{content_len}, 'bytes of content');
      }
      my $have_len = $packet->{content_len} || $packet->{data_len};
      map { $have_len += $_->{data_len} }
         @{$session->{packets}};
      $session->{have_all_packets}
         = 1 if $session->{attribs}->{bytes}
                && $have_len >= $session->{attribs}->{bytes};
      MKDEBUG && _d('Have', $have_len, 'of', $session->{attribs}->{bytes});
      return;
   }

   # Assume that the server is returning only one value. 
   # TODO: make it handle multiple.
   if ( $session->{state} eq 'awaiting reply' ) {

      # Save this early because we may return early if the packets
      # are being received out of order.  Also, save it only once
      # in case we re-process packets if they're out of order.
      $session->{start_reply} = $packet->{ts} unless $session->{start_reply};

      # Get first line of header and first chunk of contents/data.
      my ($line1, $content) = $self->_parse_header($session, $packet->{data},
            $packet->{data_len});

      # The reponse, when in order, is text header followed by data.
      # If there's no line1, then we didn't get the text header first
      # which means we're getting the response in out of order packets.
      if ( !$line1 ) {
         $session->{out_of_order}     = 1;  # alert parent
         $session->{have_all_packets} = 0;
         return;
      }

      # First line should be: version  code phrase
      # E.g.:                 HTTP/1.1  200 OK
      my ($version, $code, $phrase) = $line1 =~ m/(\S+)/g;
      $session->{attribs}->{Status_code} = $code;
      MKDEBUG && _d('Status code for last', $session->{attribs}->{arg},
         'request:', $session->{attribs}->{Status_code});

      my $content_len = $content ? length $content : 0;
      MKDEBUG && _d('Got', $content_len, 'bytes of content');
      if ( $session->{attribs}->{bytes}
           && $content_len < $session->{attribs}->{bytes} ) {
         $session->{data_len}  = $session->{attribs}->{bytes};
         $session->{buff}      = $content;
         $session->{buff_left} = $session->{attribs}->{bytes} - $content_len;
         MKDEBUG && _d('Contents not complete,', $session->{buff_left},
            'bytes left');
         $session->{state} = 'recving content';
         return;
      }
   }
   elsif ( $session->{state} eq 'recving content' ) {
      if ( $session->{buff} ) {
         MKDEBUG && _d('Receiving content,', $session->{buff_left},
            'bytes left');
         return;
      }
      MKDEBUG && _d('Contents received');
   }
   else {
      # TODO:
      warn "Server response in unknown state"; 
      return;
   }

   MKDEBUG && _d('Creating event, deleting session');
   $session->{end_reply} = $session->{ts_max} || $packet->{ts};
   my $event = $self->make_event($session, $packet);
   delete $self->{sessions}->{$session->{client}}; # http is stateless!
   return $event;
}

# Handles a packet from the client given the state of the session.
sub _packet_from_client {
   my ( $self, $packet, $session, $misc ) = @_;
   die "I need a packet"  unless $packet;
   die "I need a session" unless $session;

   MKDEBUG && _d('Packet is from client; state:', $session->{state});

   my $event;
   if ( ($session->{state} || '') =~ m/awaiting / ) {
      MKDEBUG && _d('More client headers:', $packet->{data});
      return;
   }

   if ( !$session->{state} ) {
      $session->{state} = 'awaiting reply';
      my ($line1, undef) = $self->_parse_header($session, $packet->{data}, $packet->{data_len});
      # First line should be: request page      version
      # E.g.:                 GET     /foo.html HTTP/1.1
      my ($request, $page, $version) = $line1 =~ m/(\S+)/g;
      if ( !$request || !$page ) {
         MKDEBUG && _d("Didn't get a request or page:", $request, $page);
         return;
      }
      $request = lc $request;
      my $vh   = $session->{attribs}->{Virtual_host} || '';
      my $arg = "$request $vh$page";
      MKDEBUG && _d('arg:', $arg);

      if ( $request eq 'get' || $request eq 'post' ) {
         @{$session->{attribs}}{qw(arg)} = ($arg);
      }
      else {
         MKDEBUG && _d("Don't know how to handle a", $request, "request");
         return;
      }

      $session->{start_request}         = $packet->{ts};
      $session->{attribs}->{host}       = $packet->{src_host};
      $session->{attribs}->{pos_in_log} = $packet->{pos_in_log};
      $session->{attribs}->{ts}         = $packet->{ts};
   }
   else {
      # TODO:
      die "Probably multiple GETs from client before a server response?"; 
   }

   return $event;
}

sub _parse_header {
   my ( $self, $session, $data, $len, $no_recurse ) = @_;
   die "I need data" unless $data;
   my ($header, $content)    = split(/\r\n\r\n/, $data);
   my ($line1, $header_vals) = $header  =~ m/\A(\S+ \S+ .+?)\r\n(.+)?/s;
   MKDEBUG && _d('HTTP header:', $line1);
   return unless $line1;

   if ( !$header_vals ) {
      MKDEBUG && _d('No header vals');
      return $line1, undef;
   }
   my @headers;
   foreach my $val ( split(/\r\n/, $header_vals) ) {
      last unless $val;
      # Capture and save any useful header values.
      MKDEBUG && _d('HTTP header:', $val);
      if ( $val =~ m/^Content-Length/i ) {
         ($session->{attribs}->{bytes}) = $val =~ /: (\d+)/;
         MKDEBUG && _d('Saved Content-Length:', $session->{attribs}->{bytes});
      }
      if ( $val =~ m/Content-Encoding/i ) {
         ($session->{compressed}) = $val =~ /: (\w+)/;
         MKDEBUG && _d('Saved Content-Encoding:', $session->{compressed});
      }
      if ( $val =~ m/^Host/i ) {
         # The "host" attribute is already taken, so we call this "domain".
         ($session->{attribs}->{Virtual_host}) = $val =~ /: (\S+)/;
         MKDEBUG && _d('Saved Host:', ($session->{attribs}->{Virtual_host}));
      }
   }
   return $line1, $content;
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
# End HTTPProtocolParser package
# ###########################################################################
