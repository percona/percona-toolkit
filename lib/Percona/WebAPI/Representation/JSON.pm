package Percona::WebAPI::Representation::JSON;

use Moose::Role;
use JSON;

sub as_json {
   my ($self) = @_;

   # Copy the object into a new hashref.
   my $as_hashref = { %$self };

   # Delete the links because they're just for client-side use
   # and the caller should be sending this object, not getting it.
   delete $as_hashref->{links};

   return encode_json($as_hashref);
}

1;
