# This program is copyright 2012-2013 Percona Inc.
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
# Percona::Test::Mock::UserAgent package
# ###########################################################################
{
package Percona::Test::Mock::UserAgent;

sub new {
   my ($class, %args) = @_;
   my $self = {
      encode    => $args{encode} || sub { return $_[0] },
      decode    => $args{decode} || sub { return $_[0] },
      requests  => [],
      responses => {
         get  => [],
         post => [],
         put  => [],
      },
      content => {
         post => [],
         put  => [],
      },
      last_request => undef,
   };
   return bless $self, $class;
}

sub request {
   my ($self, $req) = @_;
   $self->{last_request} = $req; 
   my $type = lc($req->method);
   push @{$self->{requests}}, uc($type) . ' ' . $req->uri;
   if ( $type eq 'post' || $type eq 'put' ) {
      push @{$self->{content}->{$type}}, $req->content;
   }
   my $r = shift @{$self->{responses}->{$type}};
   my $c = $r->{content} ? $self->{encode}->($r->{content}) : '';
   my $h = HTTP::Headers->new;
   $h->header(%{$r->{headers}}) if exists $r->{headers};
   my $res = HTTP::Response->new(
      $r->{code} || 200,
      '',
      $h,
      $c,
   );
   return $res;
}

1;
}
# ###########################################################################
# End Percona::Test::Mock::UserAgent package
# ###########################################################################
