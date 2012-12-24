package Percona::WebAPI::Resource::Config;

use Mo;

with 'Percona::WebAPI::Representation::JSON';
with 'Percona::WebAPI::Representation::HashRef';

has 'options' => (
   is       => 'ro',
   isa      => 'HashRef',
   required => 1,
);

1;
