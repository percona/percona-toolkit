package Percona::WebAPI::Resource::Service;

use Mo;

with 'Percona::WebAPI::Representation::JSON';
with 'Percona::WebAPI::Representation::HashRef';

has 'name' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'schedule' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'run' => (
   is       => 'ro',
   isa      => 'ArrayRef[Percona::WebAPI::Resource::Run]',
   required => 1,
);

1;
