package Percona::WebAPI::Resource::Run;

use Mo;

with 'Percona::WebAPI::Representation::JSON';
with 'Percona::WebAPI::Representation::HashRef';

has 'number' => (
   is       => 'ro',
   isa      => 'Int',
   required => 1,
);

has 'program' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'options' => (
   is       => 'ro',
   isa      => 'Maybe[Str]',
   required => 0,
);

has 'output' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

1;
