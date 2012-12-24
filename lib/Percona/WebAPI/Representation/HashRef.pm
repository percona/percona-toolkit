package Percona::WebAPI::Representation::HashRef;

use Moose::Role;

sub as_hashref {
   my ($self) = @_;

   # Copy the object into a new hashref.
   my $as_hashref = { %$self };

   # Delete the links because they're just for client-side use
   # and the caller should be sending this object, not getting it.
   delete $as_hashref->{links};

   return $as_hashref;
}

1;
