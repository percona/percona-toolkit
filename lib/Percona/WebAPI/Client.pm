package Percona::WebAPI::Client;

our $VERSION = '0.01';

use LWP;
use JSON;
use Scalar::Util qw(blessed); 
use English qw(-no_match_vars);

use Percona::Toolkit;

has 'api_key' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'base_url' => (
   is       => 'rw',
   isa      => 'Str',
   default  => 'https://api.tools.percona.com',
   required => 1,
);

has 'links' => (
   is      => 'rw',
   isa     => 'HashRef',
   lazy    => 1,
   default => sub { return +{} },
);

has 'ua' => (
   is       => 'rw',
   isa      => 'LWP::UserAgent',
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
   PTDEBUG && _d('Entry links', $entry_links);

   $self->links($entry_links);

   return;
}

sub get {
   my ($self, %args) = @_;

   # Arguments:
   my @required_args = (
      'link',  # A resource link (e.g. $run->links->{results})
   );
   my ($link) = @args{@required_args};

   # Returns:
   my @resources;  # Resources from the requested link

   # Get resource representations from the link.  The server should always
   # return a list of resource reps, even if there's only one resource.
   eval {
      $self->_request(
         method => 'GET',
         url    => $link,
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

sub delete {
   my ($self, %args) = @_;

   # Arguments:
   my @required_args = (
      'link',  # A resource link (e.g. $run->links->{results})
   );
   my ($link) = @args{@required_args};

   eval {
      $self->_request(
         method  => 'DELETE',
         url     => $link,
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
   my @required_args = qw(method resources link);
   my ($method, $res, $link) = @args{@required_args};

   my $content;
   if ( ref($res) eq 'ARRAY' ) {
      $content = '[' . join(",\n", map { $_->as_json } @$res) . ']';
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
      $content = $res->as_json;
   }

   eval {
      $self->_request(
         method  => $method,
         url     => $link,
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

   my @required_args = (
      'method',
      'url',
   );
   my ($method, $url) = @args{@required_args};

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
   PTDEBUG && _d('Request', $method, $url, $req);

   my $res = $self->ua->request($req);
   PTDEBUG && _d('Response', $res);

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
   PTDEBUG && _d('Updated links', $self->links);
   return;
}

1;
