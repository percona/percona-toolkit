# This program is copyright 2007-2011 Percona Inc.
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
# MemcachedProtocolParser package $Revision: 7521 $
# ###########################################################################
{
# Package: MemcachedProtocolParser
# MemcachedProtocolParser parses memcached events from tcpdump files.
package MemcachedProtocolParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;

   my $self = {
      server      => $args{server},
      port        => $args{port} || '11211',
      sessions    => {},
      o           => $args{o},
   };
   return bless $self, $class;
}

# The packet arg should be a hashref from TcpdumpParser::parse_event().
# misc is a placeholder for future features.
sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(event);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $packet = @args{@required_args};

   # Return early if there's no TCP data.  These are usually ACK packets, but
   # they could also be FINs in which case, we should close and delete the
   # client's session.
   # TODO: It seems we don't handle FIN here?  So I moved this code block here.
   if ( $packet->{data_len} == 0 ) {
      MKDEBUG && _d('No TCP data');
      $args{stats}->{no_tcp_data}++ if $args{stats};
      return;
   }

   my $src_host = "$packet->{src_host}:$packet->{src_port}";
   my $dst_host = "$packet->{dst_host}:$packet->{dst_port}";

   if ( my $server = $self->{server} ) {  # Watch only the given server.
      $server .= ":$self->{port}";
      if ( $src_host ne $server && $dst_host ne $server ) {
         MKDEBUG && _d('Packet is not to or from', $server);
         $args{stats}->{not_watched_server}++ if $args{stats};
         return;
      }
   }

   # Auto-detect the server by looking for port 11211
   my $packet_from;
   my $client;
   if ( $src_host =~ m/:$self->{port}$/ ) {
      $packet_from = 'server';
      $client      = $dst_host;
   }
   elsif ( $dst_host =~ m/:$self->{port}$/ ) {
      $packet_from = 'client';
      $client      = $src_host;
   }
   else {
      warn 'Packet is not to or from memcached server: ', Dumper($packet);
      return;
   }
   MKDEBUG && _d('Client:', $client);

   # Get the client's session info or create a new session if the
   # client hasn't been seen before.
   if ( !exists $self->{sessions}->{$client} ) {
      MKDEBUG && _d('New session');
      $self->{sessions}->{$client} = {
         client      => $client,
         state       => undef,
         raw_packets => [],
         # ts -- wait for ts later.
      };
   };
   my $session = $self->{sessions}->{$client};

   # Save raw packets to dump later in case something fails.
   push @{$session->{raw_packets}}, $packet->{raw_packet};

   # Finally, parse the packet and maybe create an event.
   $packet->{data} = pack('H*', $packet->{data});
   my $event;
   if ( $packet_from eq 'server' ) {
      $event = $self->_packet_from_server($packet, $session, %args);
   }
   elsif ( $packet_from eq 'client' ) {
      $event = $self->_packet_from_client($packet, $session, %args);
   }
   else {
      # Should not get here.
      $args{stats}->{unknown_packet_origin}++ if $args{stats};
      die 'Packet origin unknown';
   }

   MKDEBUG && _d('Done with packet; event:', Dumper($event));
   $args{stats}->{events_parsed}++ if $args{stats};
   return $event;
}

# Handles a packet from the server given the state of the session.  Returns an
# event if one was ready to be created, otherwise returns nothing.
sub _packet_from_server {
   my ( $self, $packet, $session, %args ) = @_;
   die "I need a packet"  unless $packet;
   die "I need a session" unless $session;

   MKDEBUG && _d('Packet is from server; client state:', $session->{state}); 

   my $data = $packet->{data};

   # If there's no session state, then we're catching a server response
   # mid-stream.
   if ( !$session->{state} ) {
      MKDEBUG && _d('Ignoring mid-stream server response');
      $args{stats}->{ignored_midstream_server_response}++ if $args{stats};
      return;
   }

   # Assume that the server is returning only one value.  TODO: make it
   # handle multi-gets.
   if ( $session->{state} eq 'awaiting reply' ) {
      MKDEBUG && _d('State is awaiting reply');
      # \r\n == 0d0a
      my ($line1, $rest) = $packet->{data} =~ m/\A(.*?)\r\n(.*)?/s;
      if ( !$line1 ) {
         $args{stats}->{unknown_server_data}++ if $args{stats};
         die "Unknown memcached data from server";
      }

      # Split up the first line into its parts.
      my @vals = $line1 =~ m/(\S+)/g;
      $session->{res} = shift @vals;
      MKDEBUG && _d('Result of last', $session->{cmd}, 'cmd:', $session->{res});

      if ( $session->{cmd} eq 'incr' || $session->{cmd} eq 'decr' ) {
         MKDEBUG && _d('It is an incr or decr');
         if ( $session->{res} !~ m/\D/ ) { # It's an integer, not an error
            MKDEBUG && _d('Got a value for the incr/decr');
            $session->{val} = $session->{res};
            $session->{res} = '';
         }
      }
      elsif ( $session->{res} eq 'VALUE' ) {
         MKDEBUG && _d('It is the result of a "get"');
         my ($key, $flags, $bytes) = @vals;
         defined $session->{flags} or $session->{flags} = $flags;
         defined $session->{bytes} or $session->{bytes} = $bytes;

         # Get the value from the $rest.
         # TODO: there might be multiple responses
         if ( $rest && $bytes ) {
            MKDEBUG && _d('There is a value');
            if ( length($rest) > $bytes ) {
               MKDEBUG && _d('Got complete response');
               $session->{val} = substr($rest, 0, $bytes);
            }
            else {
               MKDEBUG && _d('Got partial response, saving for later');
               push @{$session->{partial}}, [ $packet->{seq}, $rest ];
               $session->{gathered} += length($rest);
               $session->{state} = 'partial recv';
               return; # Prevent firing an event.
            }
         }
      }
      elsif ( $session->{res} eq 'END' ) {
         # Technically NOT_FOUND is an error, and this isn't an error it's just
         # a NULL, but what it really means is the value isn't found.
         MKDEBUG && _d('Got an END without any data, firing NOT_FOUND');
         $session->{res} = 'NOT_FOUND';
      }
      elsif ( $session->{res} !~ m/STORED|DELETED|NOT_FOUND/ ) {
         # Not really sure what else would get us here... want to make a note
         # and not have an uncaught condition.
         MKDEBUG && _d('Unknown result');
      }
      else {
         $args{stats}->{unknown_server_response}++ if $args{stats};
      }
   }
   else { # Should be 'partial recv'
      MKDEBUG && _d('Session state: ', $session->{state});
      push @{$session->{partial}}, [ $packet->{seq}, $data ];
      $session->{gathered} += length($data);
      MKDEBUG && _d('Gathered', $session->{gathered}, 'bytes in',
         scalar(@{$session->{partial}}), 'packets from server');
      if ( $session->{gathered} >= $session->{bytes} + 2 ) { # Done.
         MKDEBUG && _d('End of partial response, preparing event');
         my $val = join('',
            map  { $_->[1] }
            # Sort in proper sequence because TCP might reorder them.
            sort { $a->[0] <=> $b->[0] }
                 @{$session->{partial}});
         $session->{val} = substr($val, 0, $session->{bytes});
      }
      else {
         MKDEBUG && _d('Partial response continues, no action');
         return; # Prevent firing event.
      }
   }

   MKDEBUG && _d('Creating event, deleting session');
   my $event = make_event($session, $packet);
   delete $self->{sessions}->{$session->{client}}; # memcached is stateless!
   $session->{raw_packets} = []; # Avoid keeping forever
   return $event;
}

# Handles a packet from the client given the state of the session.
sub _packet_from_client {
   my ( $self, $packet, $session, %args ) = @_;
   die "I need a packet"  unless $packet;
   die "I need a session" unless $session;

   MKDEBUG && _d('Packet is from client; state:', $session->{state});

   my $event;
   if ( ($session->{state} || '') =~m/awaiting reply|partial recv/ ) {
      # Whoa, we expected something from the server, not the client.  Fire an
      # INTERRUPTED with what we've got, and create a new session.
      MKDEBUG && _d("Expected data from the client, looks like interrupted");
      $session->{res} = 'INTERRUPTED';
      $event = make_event($session, $packet);
      my $client = $session->{client};
      delete @{$session}{keys %$session};
      $session->{client} = $client;
   }

   my ($line1, $val);
   my ($cmd, $key, $flags, $exptime, $bytes);
   
   if ( !$session->{state} ) {
      MKDEBUG && _d('Session state: ', $session->{state});
      # Split up the first line into its parts.
      ($line1, $val) = $packet->{data} =~ m/\A(.*?)\r\n(.+)?/s;
      if ( !$line1 ) {
         MKDEBUG && _d('Unknown memcached data from client, skipping packet');
         $args{stats}->{unknown_client_data}++ if $args{stats};
         return;
      }

      # TODO: handle <cas unique> and [noreply]
      my @vals = $line1 =~ m/(\S+)/g;
      $cmd = lc shift @vals;
      MKDEBUG && _d('$cmd is a ', $cmd);
      if ( $cmd eq 'set' || $cmd eq 'add' || $cmd eq 'replace' ) {
         ($key, $flags, $exptime, $bytes) = @vals;
         $session->{bytes} = $bytes;
      }
      elsif ( $cmd eq 'get' ) {
         ($key) = @vals;
         if ( $val ) {
            MKDEBUG && _d('Multiple cmds:', $val);
            $val = undef;
         }
      }
      elsif ( $cmd eq 'delete' ) {
         ($key) = @vals; # TODO: handle the <queue_time>
         if ( $val ) {
            MKDEBUG && _d('Multiple cmds:', $val);
            $val = undef;
         }
      }
      elsif ( $cmd eq 'incr' || $cmd eq 'decr' ) {
         ($key) = @vals;
      }
      else {
         MKDEBUG && _d("Don't know how to handle", $cmd, "command");
         $args{stats}->{unknown_client_command}++ if $args{stats};
         return;
      }

      @{$session}{qw(cmd key flags exptime)}
         = ($cmd, $key, $flags, $exptime);
      $session->{host}       = $packet->{src_host};
      $session->{pos_in_log} = $packet->{pos_in_log};
      $session->{ts}         = $packet->{ts};
   }
   else {
      MKDEBUG && _d('Session state: ', $session->{state});
      $val = $packet->{data};
   }

   # Handle the rest of the packet.  It might not be the whole value that was
   # sent, for example for a big set().  We need to look at the number of bytes
   # and see if we got it all.
   $session->{state} = 'awaiting reply'; # Assume we got the whole packet
   if ( $val ) {
      if ( $session->{bytes} + 2 == length($val) ) { # +2 for the \r\n
         MKDEBUG && _d('Complete send');
         $val =~ s/\r\n\Z//; # We got the whole thing.
         $session->{val} = $val;
      }
      else { # We apparently did NOT get the whole thing.
         MKDEBUG && _d('Partial send, saving for later');
         push @{$session->{partial}},
            [ $packet->{seq}, $val ];
         $session->{gathered} += length($val);
         MKDEBUG && _d('Gathered', $session->{gathered}, 'bytes in',
            scalar(@{$session->{partial}}), 'packets from client');
         if ( $session->{gathered} >= $session->{bytes} + 2 ) { # Done.
            MKDEBUG && _d('Message looks complete now, saving value');
            $val = join('',
               map  { $_->[1] }
               # Sort in proper sequence because TCP might reorder them.
               sort { $a->[0] <=> $b->[0] }
                    @{$session->{partial}});
            $val =~ s/\r\n\Z//;
            $session->{val} = $val;
         }
         else {
            MKDEBUG && _d('Message not complete');
            $val = '[INCOMPLETE]';
            $session->{state} = 'partial send';
         }
      }
   }

   return $event;
}

# The event is not yet suitable for mk-query-digest.  It lacks, for example,
# an arg and fingerprint attribute.  The event should be passed to
# MemcachedEvent::make_event() to transform it.
sub make_event {
   my ( $session, $packet ) = @_;
   my $event = {
      cmd        => $session->{cmd},
      key        => $session->{key},
      val        => $session->{val} || '',
      res        => $session->{res},
      ts         => $session->{ts},
      host       => $session->{host},
      flags      => $session->{flags}   || 0,
      exptime    => $session->{exptime} || 0,
      bytes      => $session->{bytes}   || 0,
      Query_time => timestamp_diff($session->{ts}, $packet->{ts}),
      pos_in_log => $session->{pos_in_log},
   };
   return $event;
}

sub _get_errors_fh {
   my ( $self ) = @_;
   my $errors_fh = $self->{errors_fh};
   return $errors_fh if $errors_fh;

   # Errors file isn't open yet; try to open it.
   my $o = $self->{o};
   if ( $o && $o->has('tcpdump-errors') && $o->got('tcpdump-errors') ) {
      my $errors_file = $o->get('tcpdump-errors');
      MKDEBUG && _d('tcpdump-errors file:', $errors_file);
      open $errors_fh, '>>', $errors_file
         or die "Cannot open tcpdump-errors file $errors_file: $OS_ERROR";
   }

   $self->{errors_fh} = $errors_fh;
   return $errors_fh;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

# Returns the difference between two tcpdump timestamps.  TODO: this is in
# MySQLProtocolParser too, best to factor it out somewhere common.
sub timestamp_diff {
   my ( $start, $end ) = @_;
   my $sd = substr($start, 0, 11, '');
   my $ed = substr($end,   0, 11, '');
   my ( $sh, $sm, $ss ) = split(/:/, $start);
   my ( $eh, $em, $es ) = split(/:/, $end);
   my $esecs = ($eh * 3600 + $em * 60 + $es);
   my $ssecs = ($sh * 3600 + $sm * 60 + $ss);
   if ( $sd eq $ed ) {
      return sprintf '%.6f', $esecs - $ssecs;
   }
   else { # Assume only one day boundary has been crossed, no DST, etc
      return sprintf '%.6f', ( 86_400 - $ssecs ) + $esecs;
   }
}

1;
}
# ###########################################################################
# End MemcachedProtocolParser package
# ###########################################################################
