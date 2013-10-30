# This program is copyright 2012 codenode LLC, 2012-2013 Percona Ireland Ltd.
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
# Percona::WebAPI::Client package
# ###########################################################################
{
package Percona::WebAPI::Client;

our $VERSION = '0.01';

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

eval {
   require LWP;
   require JSON;
};

use Scalar::Util qw(blessed); 

use Lmo;
use Percona::Toolkit;
use Percona::WebAPI::Representation;
use Percona::WebAPI::Exception::Request;
use Percona::WebAPI::Exception::Resource;

Percona::WebAPI::Representation->import(qw(as_json));
Percona::Toolkit->import(qw(_d Dumper have_required_args));

has 'api_key' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'entry_link' => (
   is       => 'rw',
   isa      => 'Str',
   required => 0,
   default  => sub { return 'https://cloud-api.percona.com' },
);

has 'ua' => (
   is       => 'rw',
   isa      => 'Object',
   lazy     => 1,
   required => 0,
   builder  => '_build_ua',
);

has 'response' => (
   is       => 'rw',
   isa      => 'Object',
   required => 0,
   default  => undef,
);

sub _build_ua {
   my $self = shift;
   my $ua = LWP::UserAgent->new;
   $ua->agent("Percona::WebAPI::Client/$Percona::WebAPI::Client::VERSION");
   $ua->default_header('Content-Type', 'application/json');
   $ua->default_header('X-Percona-API-Key', $self->api_key);
   return $ua;
}

sub get {
   my ($self, %args) = @_;
   
   have_required_args(\%args, qw(
      link
   )) or die;
   my ($link) = $args{link};

   # Get the resources at the link.
   eval {
      $self->_request(
         method => 'GET',
         link   => $link,
      );
   };
   if ( my $e = $EVAL_ERROR ) {
      if (blessed($e) && $e->isa('Percona::WebAPI::Exception::Request')) {
         die $e;
      }
      else {
         die "Unknown error: $e";
      }
   }

   # The resource should be represented as JSON, decode it.
   my $resource = eval {
      JSON::decode_json($self->response->content);
   };
   if ( $EVAL_ERROR ) {
      warn sprintf "Error decoding resource: %s: %s",
         $self->response->content,
         $EVAL_ERROR;
      return;
   }

   # If the server tells us the resource's type, create a new object
   # of that type.  Else, if there's no type, there's no resource, so
   # we should have received links.  This usually only happens for the
   # entry link.  The returned resource objects ref may be scalar or
   # an arrayref; the caller should know.
   my $resource_objects;
   if ( my $type = $self->response->headers->{'x-percona-resource-type'} ) {
      eval {
         $type = "Percona::WebAPI::Resource::$type";
         if ( ref $resource eq 'ARRAY' ) {
            PTDEBUG && _d('Got a list of', $type, 'resources');
            $resource_objects = [];
            foreach my $attribs ( @$resource ) {
               my $obj = $type->new(%$attribs);
               push @$resource_objects, $obj;
            }
         }
         else {
            PTDEBUG && _d('Got a', $type, 'resource', Dumper($resource));
            $resource_objects = $type->new(%$resource);
         }
      };
      if ( my $e = $EVAL_ERROR ) {
         die Percona::WebAPI::Exception::Resource->new(
            type  => $type,
            link  => $link,
            data  => (ref $resource eq 'ARRAY' ? $resource : [ $resource ]),
            error => $e,
         );
      }
   }
   elsif ( exists $resource->{links} ) {
      # Lie to the caller: this isn't an object, but the caller can
      # treat it like one, e.g. my $links = $api->get(<entry links>);
      # then access $links->{self}.  A Links object couldn't have
      # dynamic attribs anyway, so no use having a real Links obj.
      $resource_objects = $resource->{links};
   }
   elsif ( exists $resource->{pong} ) {
      PTDEBUG && _d("Ping pong!");
   }
   else {
      warn "Did not get X-Percona-Resource-Type or links from $link\n";
   }

   return $resource_objects;
}

# For a successful POST, the server sets the Location header with
# the URI of the newly created resource.
sub post {
   my $self = shift;
   $self->_set(
      @_,
      method => 'POST',
   );
   return $self->response->header('Location');
}

sub put {
   my $self = shift;
   $self->_set(
      @_,
      method => 'PUT',
   );
   return $self->response->header('Location');
}

sub delete {
   my ($self, %args) = @_;
   have_required_args(\%args, qw(
      link 
   )) or die;
   my ($link) = $args{link};

   eval {
      $self->_request(
         method  => 'DELETE',
         link    => $link,
         headers => { 'Content-Length' => 0 },
      ); 
   };
   if ( my $e = $EVAL_ERROR ) {
      if (blessed($e) && $e->isa('Percona::WebAPI::Exception::Request')) {
         die $e;
      }
      else {
         die "Unknown error: $e";
      }
   }

   return;
}

# Low-level POST and PUT handler.
sub _set {
   my ($self, %args) = @_;
   have_required_args(\%args, qw(
      method
      resources
      link
   )) or die;
   my $method = $args{method};
   my $res    = $args{resources};
   my $link   = $args{link};

   # Optional args
   my $headers = $args{headers};

   my $content = '';
   if ( ref($res) eq 'ARRAY' ) {
      PTDEBUG && _d('List of resources');
      $content = '[' . join(",\n", map { as_json($_) } @$res) . ']';
   }
   elsif ( ref($res) ) {
      PTDEBUG && _d('Resource object');
      $content = as_json($res);
   }
   elsif ( $res !~ m/\n/ && -f $res ) {
      PTDEBUG && _d('List of resources in file', $res);
      $content = '[';
      my $data = do {
         local $INPUT_RECORD_SEPARATOR = undef;
         open my $fh, '<', $res
            or die "Error opening $res: $OS_ERROR";
         <$fh>;
      };
      $data =~ s/,?\s*$/]/;
      $content .= $data;
   }
   else {
      PTDEBUG && _d('Resource text');
      $content = $res;
   }

   eval {
      $self->_request(
         method  => $method,
         link    => $link,
         content => $content,
         headers => $headers,
      );
   };
   if ( my $e = $EVAL_ERROR ) {
      if (blessed($e) && $e->isa('Percona::WebAPI::Exception::Request')) {
         die $e;
      }
      else {
         die "Unknown error: $e";
      }
   }

   return;
}

# Low-level HTTP request handler for all methods.  Sets $self->response
# from the request.  Returns nothing on success (HTTP status 2xx-3xx),
# else throws an Percona::WebAPI::Exception::Request.
sub _request {
   my ($self, %args) = @_;

   have_required_args(\%args, qw(
      method
      link 
   )) or die;
   my $method = $args{method};
   my $link   = $args{link};
   
   # Optional args
   my $content = $args{content};
   my $headers = $args{headers};

   my $req = HTTP::Request->new($method => $link);
   if ( $content ) {
      $req->content($content);
   }
   if ( $headers ) {
      map { $req->header($_ => $headers->{$_}) } keys %$headers;
   }
   PTDEBUG && _d('Request', $method, $link, Dumper($req));

   my $response = $self->ua->request($req);
   PTDEBUG && _d('Response', Dumper($response));

   $self->response($response);

   if ( !($response->code >= 200 && $response->code < 400) ) {
      die Percona::WebAPI::Exception::Request->new(
         method  => $method,
         url     => $link,
         content => $content,
         status  => $response->code,
         error   => "Failed to $method $link",
      );
   }

   return;
}

no Lmo;
1;
}
# ###########################################################################
# End Percona::WebAPI::Client package
# ###########################################################################
