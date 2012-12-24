package Percona::WebAPI::Resource::Versions;

use Mo;

with 'Percona::WebAPI::Representation::JSON';
with 'Percona::WebAPI::Representation::HashRef';

has 'versions' => (
   is       => 'ro',
   isa      => 'HashRef',
   required => 1,
);

1;
