use strict;
use warnings qw( FATAL all );

use Carp ();
use Scalar::Util qw(looks_like_number blessed);

{
   package Lmo::Meta;
   my %metadata_for;

   sub new {
      shift;
      return Lmo::Meta::Class->new(@_);
   }
   
   sub metadata_for {
      my $self    = shift;
      my ($class) = @_;

      return $metadata_for{$class} ||= {};
   }
}

{
   package Lmo::Meta::Class;

   sub new {
      my $class = shift;
      return bless { @_ }, $class
   }

   sub class { shift->{class} }

   sub attributes {
      my $self = shift;
      return keys %{Lmo::Meta->metadata_for($self->class)}
   }

   sub attributes_for_new {
      my $self = shift;
      my @attributes;

      my $class_metadata = Lmo::Meta->metadata_for($self->class);
      while ( my ($attr, $meta) = each %$class_metadata ) {
         if ( exists $meta->{init_arg} ) {
            push @attributes, $meta->{init_arg}
                  if defined $meta->{init_arg};
         }
         else {
            push @attributes, $attr;
         }
      }
      return @attributes;
   }
}

1;
