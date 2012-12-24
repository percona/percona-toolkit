package Percona::WebAPI::Resource::Agent;

use Mo;

with 'Percona::WebAPI::Representation::JSON';
with 'Percona::WebAPI::Representation::HashRef';

has 'id' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'hostname' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
   default  => sub { return `hostname 2>/dev/null` },
);

has 'versions' => (
   is       => 'ro',
   isa      => 'Maybe[Percona::WebAPI::Resource::Versions]',
   required => 0,
   default  => undef,
);

1;
