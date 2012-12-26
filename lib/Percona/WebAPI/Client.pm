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
# Percona::WebAPI::Client package
# ###########################################################################
{
package Percona::WebAPI::Client;

our $VERSION = '0.01';

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use LWP;
use JSON;
use Scalar::Util qw(blessed); 
use English qw(-no_match_vars);

use Lmo;
use Percona::Toolkit;
use Percona::WebAPI::Representation;
use Percona::WebAPI::Exception::Request;

Percona::WebAPI::Representation->import(qw(as_json));
Percona::Toolkit->import(qw(_d Dumper have_required_args));

has 'api_key' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'base_url' => (
   is       => 'rw',
   isa      => 'Str',
   default  => sub { return 'https://api.tools.percona.com' },
   required => 0,
);

has 'links' => (
   is      => 'rw',
   isa     => 'HashRef',
   lazy    => 1,
   default => sub { return +{} },
);

has 'ua' => (
   is       => 'rw',
   isa      => 'Object',
   lazy     => 1,
   required => 1,
   builder  => '_build_ua',
);

has 'response' => (
   is  => 'rw',
   isa => 'Object',
);

sub _build_ua {
   my $self = shift;
   my $ua = LWP::UserAgent->new;
   $ua->agent("Percona::WebAPI::Client/$Percona::WebAPI::Client::VERSION");
   $ua->default_header('application/json');
   $ua->default_header('X-Percona-API-Key', $self->api_key);
   return $ua;
}

sub BUILD {
   my ($self) = @_;

   eval {
      $self->_request(
         method => 'GET',
         url    => $self->base_url,
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

   my $entry_links = decode_json($self->response->content);
   PTDEBUG && _d('Entry links', Dumper($entry_links));

   $self->links($entry_links);

   return;
}

sub get {
   my ($self, %args) = @_;
   
   have_required_args(\%args, qw(
      url
   )) or die;
   my ($url) = $args{url};

   # Returns:
   my @resources;

   # Get resource representations from the url.  The server should always
   # return a list of resource reps, even if there's only one resource.
   eval {
      $self->_request(
         method => 'GET',
         url    => $url,
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

   # Transform the resource representations into an arrayref of hashrefs.
   # Each hashref contains (hopefully) all the attribs necessary to create
   # a corresponding resource object.
   my $res;
   eval {
      $res = decode_json($self->response->content);
   };
   if ( $EVAL_ERROR ) {
      warn sprintf "Error decoding resource: %s: %s",
         $self->response->content,
         $EVAL_ERROR;
      return;
   }

   my $objs;
   my $res_type = $self->response->headers->{'x-percona-webapi-content-type'};
   if ( $res_type ) {
      eval {
         my $type = "Percona::WebAPI::Resource::$res_type";

         # Create resource objects using the server-provided attribs.
         if ( ref $res->{content} eq 'ARRAY' ) {
            PTDEBUG && _d('Got a list of', $res_type, 'resources');
            foreach my $attribs ( @{$res->{content}} ) {
               my $obj = $type->new(%$attribs);
               push @$objs, $obj;
            }
         }
         else {
            PTDEBUG && _d('Got a', $res_type, 'resource');
            $objs = $type->new(%{$res->{content}});
         }
      };
      if ( $EVAL_ERROR ) {
         warn "Error creating $res_type resource objects: $EVAL_ERROR";
         return;
      }
   }

   $self->update_links($res->{links});

   return $objs;
}

sub post {
   my $self = shift;
   return $self->_set(
      @_,
      method => 'POST',
   );
}

sub put {
   my $self = shift;
   return $self->_set(
      @_,
      method => 'PUT',
   );
}

sub delete {
   my ($self, %args) = @_;

   have_required_args(\%args, qw(
      url
   )) or die;
   my ($url) = $args{url};

   eval {
      $self->_request(
         method  => 'DELETE',
         url     => $url,
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

sub _set {
   my ($self, %args) = @_;

   have_required_args(\%args, qw(
      method
      resources
      url
   )) or die;
   my $method = $args{method};
   my $res    = $args{resources};
   my $url    = $args{url};

   my $content;
   if ( ref($res) eq 'ARRAY' ) {
      $content = '[' . join(",\n", map { as_json($_) } @$res) . ']';
   }
   elsif ( -f $res ) {
      PTDEBUG && _d('Reading content from file', $res);
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
      $content = as_json($res);
   }

   eval {
      $self->_request(
         method  => $method,
         url     => $url,
         content => $content,
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

   my $links;
   eval {
      $links = decode_json($self->response->content);
   };
   if ( $EVAL_ERROR ) {
      warn sprintf "Error decoding resource: %s: %s",
         $self->response->content,
         $EVAL_ERROR;
      return;
   }

   $self->update_links($links);

   return;
}

sub _request {
   my ($self, %args) = @_;

   have_required_args(\%args, qw(
      method
      url
   )) or die;
   my $method = $args{method};
   my $url    = $args{url};

   my @optional_args = (
      'content',
      'headers',
   );
   my ($content, $headers) = @args{@optional_args};

   my $req = HTTP::Request->new($method => $url);
   $req->content($content) if $content;
   if ( uc($method) eq 'DELETE' ) {
      $self->ua->default_header('Content-Length' => 0);
   }
   PTDEBUG && _d('Request', $method, $url, Dumper($req));

   my $res = $self->ua->request($req);
   PTDEBUG && _d('Response', Dumper($res));

   if ( uc($method) eq 'DELETE' ) {
      $self->ua->default_header('Content-Length' => undef);
   }

   if ( !($res->code >= 200 && $res->code < 400) ) {
      die Percona::WebAPI::Exception::Request->new(
         method  => $method,
         url     => $url,
         content => $content,
         status  => $res->code,
         error   => $res->content,
      );
   }

   $self->response($res);

   return;
}

sub update_links {
   my ($self, $new_links) = @_;
    while (my ($svc, $links) = each %$new_links) {
      while (my ($rel, $link) = each %$links) {
         $self->links->{$svc}->{$rel} = $link;
      }
   }
   PTDEBUG && _d('Updated links', Dumper($self->links));
   return;
}

no Lmo;
1;
}
# ###########################################################################
# End Percona::WebAPI::Client package
# ###########################################################################
