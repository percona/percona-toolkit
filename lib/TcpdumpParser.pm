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
# TcpdumpParser package
# ###########################################################################
{
# Package: TcpdumpParser
# TcpdumpParser parses TCP packets from tcpdump files.
# It expects the output to be formatted a certain way.
# See the t/samples/tcpdumpxxx.txt files for examples.
# Here's a sample command on Ubuntu to produce the right formatted output:
# tcpdump -i lo port 3306 -s 1500 -x -n -q -tttt
package TcpdumpParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = {};
   return bless $self, $class;
}

# This method accepts an open filehandle and callback functions.
# It reads packets from the filehandle and calls the callbacks with each packet.
# $misc is some placeholder for the future and for compatibility with other
# query sources.
#
# Each packet is a hashref of attribute => value pairs like:
#
#  my $packet = {
#     ts          => '2009-04-12 21:18:40.638244',
#     src_host    => '192.168.1.5',
#     src_port    => '54321',
#     dst_host    => '192.168.1.1',
#     dst_port    => '3306',
#     complete    => 1|0,    # If this packet is a fragment or not
#     ip_hlen     => 5,      # Number of 32-bit words in IP header
#     tcp_hlen    => 8,      # Number of 32-bit words in TCP header
#     dgram_len   => 140,    # Length of entire datagram, IP+TCP+data, in bytes
#     data_len    => 30      # Length of data in bytes
#     data        => '...',  # TCP data
#     pos_in_log  => 10,     # Position of this packet in the log
#  };
#
# Returns the number of packets parsed.  The sub is called parse_event
# instead of parse_packet because mk-query-digest expects this for its
# modular parser objects.
sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(next_event tell);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($next_event, $tell) = @args{@required_args};

   # We read a packet at a time.  Assuming that all packets begin with a
   # timestamp "20.....", we just use that as the separator, and restore it.
   # This will be good until the year 2100.
   local $INPUT_RECORD_SEPARATOR = "\n20";

   my $pos_in_log = $tell->();
   while ( defined(my $raw_packet = $next_event->()) ) {
      next if $raw_packet =~ m/^$/;  # issue 564
      $pos_in_log -= 1 if $pos_in_log;

      # Remove the separator from the packet, and restore it to the front if
      # necessary.
      $raw_packet =~ s/\n20\Z//;
      $raw_packet = "20$raw_packet" unless $raw_packet =~ m/\A20/;

      # Remove special headers (e.g. vlan) before the IPv4 header.
      # The vast majority of IPv4 headers begin with 4508 (or 4500).  
      # http://code.google.com/p/maatkit/issues/detail?id=906
      $raw_packet =~ s/0x0000:.+?(450.) /0x0000:  $1 /;

      my $packet = $self->_parse_packet($raw_packet);
      $packet->{pos_in_log} = $pos_in_log;
      $packet->{raw_packet} = $raw_packet;

      $args{stats}->{events_read}++ if $args{stats};

      return $packet;
   }

   $args{oktorun}->(0) if $args{oktorun};
   return;
}

# Takes a hex description of a TCP/IP packet and returns the interesting bits.
sub _parse_packet {
   my ( $self, $packet ) = @_;
   die "I need a packet" unless $packet;

   my ( $ts, $source, $dest )  = $packet =~ m/\A(\S+ \S+).*? IP .*?(\S+) > (\S+):/;
   my ( $src_host, $src_port ) = $source =~ m/((?:\d+\.){3}\d+)\.(\w+)/;
   my ( $dst_host, $dst_port ) = $dest   =~ m/((?:\d+\.){3}\d+)\.(\w+)/;

   # Change ports from service name to number.
   $src_port = $self->port_number($src_port);
   $dst_port = $self->port_number($dst_port);
   
   my $hex = qr/[0-9a-f]/;
   (my $data = join('', $packet =~ m/\s+0x$hex+:\s((?:\s$hex{2,4})+)/go)) =~ s/\s+//g; 

   # Find length information in the IPv4 header.  Typically 5 32-bit
   # words.  See http://en.wikipedia.org/wiki/IPv4#Header
   my $ip_hlen = hex(substr($data, 1, 1)); # Num of 32-bit words in header.
   # The total length of the entire datagram, including header.  This is
   # useful because it lets us see whether we got the whole thing.
   my $ip_plen = hex(substr($data, 4, 4)); # Num of BYTES in IPv4 datagram.
   my $complete = length($data) == 2 * $ip_plen ? 1 : 0;

   # Same thing in a different position, with the TCP header.  See
   # http://en.wikipedia.org/wiki/Transmission_Control_Protocol.
   my $tcp_hlen = hex(substr($data, ($ip_hlen + 3) * 8, 1));

   # Get sequence and ack numbers.
   my $seq = hex(substr($data, ($ip_hlen + 1) * 8, 8));
   my $ack = hex(substr($data, ($ip_hlen + 2) * 8, 8));

   my $flags = hex(substr($data, (($ip_hlen + 3) * 8) + 2, 2));

   # Throw away the IP and TCP headers.
   $data = substr($data, ($ip_hlen + $tcp_hlen) * 8);

   my $pkt = {
      ts        => $ts,
      seq       => $seq,
      ack       => $ack,
      fin       => $flags & 0x01,
      syn       => $flags & 0x02,
      rst       => $flags & 0x04,
      src_host  => $src_host,
      src_port  => $src_port,
      dst_host  => $dst_host,
      dst_port  => $dst_port,
      complete  => $complete,
      ip_hlen   => $ip_hlen,
      tcp_hlen  => $tcp_hlen,
      dgram_len => $ip_plen,
      data_len  => $ip_plen - (($ip_hlen + $tcp_hlen) * 4),
      data      => $data ? substr($data, 0, 10).(length $data > 10 ? '...' : '')
                         : '',
   };
   PTDEBUG && _d('packet:', Dumper($pkt));
   $pkt->{data} = $data;
   return $pkt;
}

sub port_number {
   my ( $self, $port ) = @_;
   return unless $port;
   return $port eq 'mysql' ? 3306 : $port;
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
# End TcpdumpParser package
# ###########################################################################
