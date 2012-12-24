package Percona::WebAPI::Exception::Request;

use Mo;
use overload '""' => \&as_string;

has 'method' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'url' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'content' => (
   is       => 'ro',
   isa      => 'Maybe[Str]',
   required => 0,
);

has 'status' => (
   is       => 'ro',
   isa      => 'Int',
   required => 1,
);

has 'error' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

sub as_string {
   my $self = shift;
   chomp(my $error = $self->error);
   $error =~ s/\n/ /g;
   return sprintf "Error: %s\nStatus: %d\nRequest: %s %s %s\n",
      $error, $self->status, $self->method, $self->url, $self->content || '';
}

1;
