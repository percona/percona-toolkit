# Mo::Object is the parent of every Mo-derived object. Here's where new
# and BUILDARGS gets inherited from.
package Lmo::Object;

use strict;
use warnings qw( FATAL all );

use Carp ();
use Scalar::Util qw(looks_like_number blessed);

use Lmo::Meta;

{
   # Gets the glob from a given string.
   no strict 'refs';
   sub _glob_for {
      return \*{shift()}
   }
}

sub new {
   my $class = shift;
   my $args  = $class->BUILDARGS(@_);

   my $class_metadata = Lmo::Meta->metadata_for($class);

   my @args_to_delete;
   while ( my ($attr, $meta) = each %$class_metadata ) {
      next unless exists $meta->{init_arg};
      my $init_arg = $meta->{init_arg};

      # If init_arg is defined, then we
      if ( defined $init_arg ) {
         $args->{$attr} = delete $args->{$init_arg};
      }
      else {
         push @args_to_delete, $attr;
      }
   }

   delete $args->{$_} for @args_to_delete;

   for my $attribute ( keys %$args ) {
      # coerce
      if ( my $coerce = $class_metadata->{$attribute}{coerce} ) {
         $args->{$attribute} = $coerce->($args->{$attribute});
      }
      # isa
      if ( my $isa_check = $class_metadata->{$attribute}{isa} ) {
         my ($check_name, $check_sub) = @$isa_check;
         $check_sub->($args->{$attribute});
      }
   }

   while ( my ($attribute, $meta) = each %$class_metadata ) {
      next unless $meta->{required};
      Carp::confess("Attribute ($attribute) is required for $class")
         if ! exists $args->{$attribute}
   }

   my $self = bless $args, $class;

   # BUILD
   my @build_subs;
   my $linearized_isa = mro::get_linear_isa($class);

   for my $isa_class ( @$linearized_isa ) {
      unshift @build_subs, *{ _glob_for "${isa_class}::BUILD" }{CODE};
   }
   # If &class::BUILD exists, for every class in
   # the linearized ISA, call it.
   # XXX I _think_ that this uses exists correctly, since
   # a class could define a stub for BUILD and then AUTOLOAD
   # the body. Should check what Moose does.
   my @args = %$args;
   for my $sub (grep { defined($_) && exists &$_ } @build_subs) {
      # @args must be defined outside of this loop,
      # as changes to @_ in one BUILD should propagate to another
      $sub->( $self, @args);
   }
   return $self;
}

# Base BUILDARGS.
sub BUILDARGS {
   shift; # No need for the classname
   if ( @_ == 1 && ref($_[0]) ) {
      Carp::confess("Single parameters to new() must be a HASH ref, not $_[0]")
         unless ref($_[0]) eq ref({});
      return {%{$_[0]}} # We want a new reference, always
   }
   else {
      return { @_ };
   }
}

sub meta {
   my $class = shift;
   $class = Scalar::Util::blessed($class) || $class;
   return Lmo::Meta->new(class => $class);
}


1;
