# This program is copyright 2007-2011 Baron Schwartz, 2012 Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
# ###########################################################################
# Mo package
# ###########################################################################
# Package: Mo
# Mo provides a miniature object system in the style of Moose and Moo.
BEGIN {
$INC{"Mo.pm"} = __FILE__;
package Mo;
our $VERSION = '0.30_Percona'; # Forked from 0.30 of Mo.

{
   # Gets the glob from a given string.
   no strict 'refs';
   sub _glob_for {
      return \*{shift()}
   }

   # Gets the stash from a given string. A larger explanation about hashes in Mo::Percona
   sub _stash_for {
      return \%{ shift() . "::" };
   }
}

use strict;
use warnings qw( FATAL all );

use Carp ();
use Scalar::Util qw(looks_like_number blessed);

# Basic types for isa. If you want a new type, either add it here,
# or give isa a coderef.

our %TYPES = (
   Bool   => sub { !$_[0] || (defined $_[0] && looks_like_number($_[0]) && $_[0] == 1) },
   Num    => sub { defined $_[0] && looks_like_number($_[0]) },
   Int    => sub { defined $_[0] && looks_like_number($_[0]) && $_[0] == int($_[0]) },
   Str    => sub { defined $_[0] },
   Object => sub { defined $_[0] && blessed($_[0]) },
   FileHandle => sub { local $@; require IO::Handle; fileno($_[0]) && $_[0]->opened },

   map {
      my $type = /R/ ? $_ : uc $_;
      $_ . "Ref" => sub { ref $_[0] eq $type }
   } qw(Array Code Hash Regexp Glob Scalar)
);

our %metadata_for;
{
   # Mo::Object is the parent of every Mo-derived object. Here's where new
   # and BUILDARGS gets inherited from.
   package Mo::Object;

   sub new {
      my $class = shift;
      my $args  = $class->BUILDARGS(@_);

      my @args_to_delete;
      while ( my ($attr, $meta) = each %{$metadata_for{$class}} ) {
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
         if ( my $coerce = $metadata_for{$class}{$attribute}{coerce} ) {
            $args->{$attribute} = $coerce->($args->{$attribute});
         }
         # isa
         if ( my $I = $metadata_for{$class}{$attribute}{isa} ) {
            ( (my $I_name), $I ) = @{$I};
            Mo::_check_type_constaints($attribute, $I, $I_name, $args->{$attribute});
         }
      }

      while ( my ($attribute, $meta) = each %{$metadata_for{$class}} ) {
         next unless $meta->{required};
         Carp::confess("Attribute ($attribute) is required for $class")
            if ! exists $args->{$attribute}
      }

      @_ = %$args;
      my $self = bless $args, $class;

      # BUILD
      my @build_subs;
      my $linearized_isa = mro::get_linear_isa($class);

      for my $isa_class ( @$linearized_isa ) {
         unshift @build_subs, *{ Mo::_glob_for "${isa_class}::BUILD" }{CODE};
      }
      # If &class::BUILD exists, for every class in
      # the linearized ISA, call it.
      # XXX I _think_ that this uses exists correctly, since
      # a class could define a stub for BUILD and then AUTOLOAD
      # the body. Should check what Moose does.
      exists &$_ && $_->( $self, @_ ) for grep { defined } @build_subs;
      return $self;
   }

   # Base BUILDARGS.
   sub BUILDARGS {
      shift;
      my $ref;
      if ( @_ == 1 && ref($_[0]) ) {
         Carp::confess("Single parameters to new() must be a HASH ref")
            unless ref($_[0]) eq ref({});
         $ref = {%{$_[0]}} # We want a new reference, always
      }
      else {
         $ref = { @_ };
      }
      return $ref;
   }
}

my %export_for;
sub Mo::import {
    # Set warnings and strict for the caller.
    warnings->import(qw(FATAL all));
    strict->import();
    
    my $caller     = scalar caller(); # Caller's package
    my $caller_pkg = $caller . "::"; # Caller's package with :: at the end
    my (%exports, %options);

    # Load each feature and call its &e.
    my (undef, @features) = @_;
    my %ignore = ( map { $_ => 1 } qw( is isa init_arg builder buildargs clearer predicate build handles default required ) );
    for my $feature (grep { !$ignore{$_} } @features) {
      { local $@; require "Mo/$feature.pm"; }
      {
         no strict 'refs';
         &{"Mo::${feature}::e"}(
                  $caller_pkg,
                  \%exports,
                  \%options,
                  \@_
            );
      }
    }

    return if $exports{M}; 

    %exports = (
        extends => sub {
            for my $class ( map { "$_" } @_ ) {
               # Try loading the class, but don't croak if we fail.
               $class =~ s{::|'}{/}g;
               { local $@; eval { require "$class.pm" } } # or warn $@;
            }
            _set_package_isa($caller, @_);
            _set_inherited_metadata($caller);
        },
        override => \&override,
        has => sub {
            my $names = shift;
            for my $attribute ( ref $names ? @$names : $names ) {
               my %args   = @_;
               my $method = ($args{is} || '') eq 'ro'
                  ? sub {
                     Carp::confess("Cannot assign a value to a read-only accessor at reader ${caller_pkg}${attribute}")
                        if $#_;
                     return $_[0]{$attribute};
                  }
                  : sub {
                     return $#_
                           ? $_[0]{$attribute} = $_[1]
                           : $_[0]{$attribute};
                  };

               $metadata_for{$caller}{$attribute} = ();

               # isa => Constaint,
               if ( my $I = $args{isa} ) {
                  my $orig_I = $I;
                  my $type;
                  if ( $I =~ /\A(ArrayRef|Maybe)\[(.*)\]\z/ ) {
                     $I = _nested_constraints($attribute, $1, $2);
                  }
                  $metadata_for{$caller}{$attribute}{isa} = [$orig_I, $I];
                  my $orig_method = $method;
                  $method = sub {
                     if ( $#_ ) {
                        Mo::_check_type_constaints($attribute, $I, $orig_I, $_[1]);
                     }
                     goto &$orig_method;
                  };
               }

               # XXX TODO: Inline builder and default into the actual method, for speed.
               # builder => '_builder_method',
               if ( my $builder = $args{builder} ) {
                  my $original_method = $method;
                  $method = sub {
                        $#_
                           ? goto &$original_method
                           : ! exists $_[0]{$attribute}
                              ? $_[0]{$attribute} = $_[0]->$builder
                              : goto &$original_method
                  };
               }

               # default => CodeRef,
               if ( my $code = $args{default} ) {
                  Carp::confess("${caller}::${attribute}'s default is $code, but should be a coderef")
                        unless ref($code) eq 'CODE';
                  my $original_method = $method;
                  $method = sub {
                        $#_
                           ? goto &$original_method
                           : ! exists $_[0]{$attribute}
                              ? $_[0]{$attribute} = $_[0]->$code
                              : goto &$original_method
                  };
               }

               # does => 'Role',
               if ( my $role = $args{does} ) {
                  my $original_method = $method;
                  $method = sub {
                     if ( $#_ ) {
                        Carp::confess(qq<Attribute ($attribute) doesn't consume a '$role' role">)
                           unless Scalar::Util::blessed($_[1]) && eval { $_[1]->does($role) }
                     }
                     goto &$original_method
                  };
               }

               # coerce => CodeRef,
               if ( my $coercion = $args{coerce} ) {
                  $metadata_for{$caller}{$attribute}{coerce} = $coercion;
                  my $original_method = $method;
                  $method = sub {
                     if ( $#_ ) {
                        return $original_method->($_[0], $coercion->($_[1]))
                     }
                     goto &$original_method;
                  }
               }

               # Call the extra features; that is, things loaded from
               # the Mo::etc namespace, and not implemented here.
               $method = $options{$_}->($method, $attribute, @_)
                  for sort keys %options;

               # Actually put the attribute's accessor in the class
               *{ _glob_for "${caller}::$attribute" } = $method;

               if ( $args{required} ) {
                  $metadata_for{$caller}{$attribute}{required} = 1;
               }

               if ($args{clearer}) {
                  *{ _glob_for "${caller}::$args{clearer}" }
                     = sub { delete shift->{$attribute} }
               }

               if ($args{predicate}) {
                  *{ _glob_for "${caller}::$args{predicate}" }
                     = sub { exists shift->{$attribute} }
               }

               if ($args{handles}) {
                  _has_handles($caller, $attribute, \%args);
               }

               if (exists $args{init_arg}) {
                  $metadata_for{$caller}{$attribute}{init_arg} = $args{init_arg};
               }
            }
        },
        %exports,
    );

    # We keep this so code doing 'no Mo;' actually does a cleanup.
    $export_for{$caller} = [ keys %exports ];

    # Export has, extends and sosuch.
    for my $keyword ( keys %exports ) {
      *{ _glob_for "${caller}::$keyword" } = $exports{$keyword}
    }
    # Set up our caller's ISA, unless they already set it manually themselves,
    # in which case we assume they know what they are doing.
    # XXX weird syntax here because we want to call the classes' extends at
    # least once, to avoid warnings.
    *{ _glob_for "${caller}::extends" }{CODE}->( "Mo::Object" )
      unless @{ *{ _glob_for "${caller}::ISA" }{ARRAY} || [] };
};

sub _check_type_constaints {
   my ($attribute, $I, $I_name, $val) = @_;
   ( ref($I) eq 'CODE'
      ? $I->($val)
      : (ref $val eq $I
         || ($val && $val eq $I)
         || (exists $TYPES{$I} && $TYPES{$I}->($val)))
   )
   || Carp::confess(
         qq<Attribute ($attribute) does not pass the type constraint because: >
      . qq<Validation failed for '$I_name' with value >
      . (defined $val ? Mo::Dumper($val) : 'undef') )
}

# handles handles
sub _has_handles {
   my ($caller, $attribute, $args) = @_;
   my $handles = $args->{handles};

   my $ref = ref $handles;
   my $kv;
   if ( $ref eq ref [] ) {
         # handles => [ ... list of methods ... ],
         $kv = { map { $_,$_ } @{$handles} };
   }
   elsif ( $ref eq ref {} ) {
         # handles => { 'method_to_install' => 'original_method' | [ 'original_method', ... curried arguments ... ], },
         $kv = $handles;
   }
   elsif ( $ref eq ref qr// ) {
         # handles => qr/PAT/,
         Carp::confess("Cannot delegate methods based on a Regexp without a type constraint (isa)")
            unless $args->{isa};
         my $target_class = $args->{isa};
         $kv = {
            map   { $_, $_     }
            grep  { $_ =~ $handles }
            grep  { !exists $Mo::Object::{$_} && $target_class->can($_) }
            grep  { $_ ne 'has' && $_ ne 'extends' }
            keys %{ _stash_for $target_class }
         };
   }
   else {
         Carp::confess("handles for $ref not yet implemented");
   }

   while ( my ($method, $target) = each %{$kv} ) {
         my $name = _glob_for "${caller}::$method";
         Carp::confess("You cannot overwrite a locally defined method ($method) with a delegation")
            if defined &$name;

         # If we have an arrayref, they are currying some arguments.
         my ($target, @curried_args) = ref($target) ? @$target : $target;
         *$name = sub {
            my $self        = shift;
            my $delegate_to = $self->$attribute();
            my $error = "Cannot delegate $method to $target because the value of $attribute";
            Carp::confess("$error is not defined") unless $delegate_to;
            Carp::confess("$error is not an object (got '$delegate_to')")
               unless Scalar::Util::blessed($delegate_to) || (!ref($delegate_to) && $delegate_to->can($target));
            return $delegate_to->$target(@curried_args, @_);
         }
   }
}

# Nested (or parametized) constraints look like this: ArrayRef[CONSTRAINT] or
# Maybe[CONSTRAINT]. This function returns a coderef that implements one of
# these.
sub _nested_constraints {
   my ($attribute, $aggregate_type, $type) = @_;

   my $inner_types;
   if ( $type =~ /\A(ArrayRef|Maybe)\[(.*)\]\z/ ) {
      # If the inner constraint -- the part within brackets -- is also a parametized
      # constraint, then call this function recursively.
      $inner_types = _nested_constraints($1, $2);
   }
   else {
      # Otherwise, try checking if it's one of the built-in types.
      $inner_types = $TYPES{$type};
   }

   if ( $aggregate_type eq 'ArrayRef' ) {
      return sub {
         my ($val) = @_;
         return unless ref($val) eq ref([]);

         if ($inner_types) {
            for my $value ( @{$val} ) {
               return unless $inner_types->($value) 
            }
         }
         else {
            # $inner_types isn't set, we are dealing with a class name.
            for my $value ( @{$val} ) {
               return unless $value && ($value eq $type
                        || (Scalar::Util::blessed($value) && $value->isa($type)));
            }
         }
         return 1;
      };
   }
   elsif ( $aggregate_type eq 'Maybe' ) {
      return sub {
         my ($value) = @_;
         # For Maybe, undef is valid
         return 1 if ! defined($value);
         # Otherwise, defer to the inner type
         if ($inner_types) {
            return unless $inner_types->($value) 
         }
         else {
            return unless $value eq $type
                        || (Scalar::Util::blessed($value) && $value->isa($type));
         }
         return 1;
      }
   }
   else {
      Carp::confess("Nested aggregate types are only implemented for ArrayRefs and Maybe");
   }
}

# Sets a package's @ISA to the list passed in. Overwrites any previous values.
sub _set_package_isa {
   my ($package, @new_isa) = @_;

   *{ _glob_for "${package}::ISA" } = [@new_isa];
}

# Each class has its own metadata. When a class inhyerits attributes,
# it should also inherit the attribute metadata.
sub _set_inherited_metadata {
   my $class = shift;
   my $linearized_isa = mro::get_linear_isa($class);
   my %new_metadata;

   # Walk @ISA in reverse, grabbing the metadata for each
   # class. Attributes with the same name defined in more
   # specific classes override their parent's attributes.
   for my $isa_class (reverse @$linearized_isa) {
      %new_metadata = (
         %new_metadata,
         %{ $metadata_for{$isa_class} || {} },
      );
   }
   $metadata_for{$class} = \%new_metadata;
}

sub unimport {
   my $caller = scalar caller();
   my $stash  = _stash_for( $caller );

   delete $stash->{$_} for @{$export_for{$caller}};
}

sub Dumper {
   require Data::Dumper;
   local $Data::Dumper::Indent    = 0;
   local $Data::Dumper::Sortkeys  = 0;
   local $Data::Dumper::Quotekeys = 0;
   local $Data::Dumper::Terse     = 1;

   Data::Dumper::Dumper(@_)
}

BEGIN {
   # mro is the method resolution order. The module itself is core in
   # recent Perls; In older Perls it's available from MRO::Compat from
   # CPAN, and in case that isn't available to us, we inline the barest
   # funcionality.
   if ($] >= 5.010) {
      { local $@; require mro; }
   }
   else {
      local $@;
      eval {
         require MRO::Compat;
      } or do {
         *mro::get_linear_isa = *mro::get_linear_isa_dfs = sub {
            no strict 'refs';

            my $classname = shift;

            my @lin = ($classname);
            my %stored;
            foreach my $parent (@{"$classname\::ISA"}) {
               my $plin = mro::get_linear_isa_dfs($parent);
               foreach (@$plin) {
                     next if exists $stored{$_};
                     push(@lin, $_);
                     $stored{$_} = 1;
               }
            }
            return \@lin;
         };
      }
   }
}

sub override {
   my ($methods, $code) = @_;
   my $caller          = scalar caller;

   for my $method ( ref($methods) ? @$methods : $methods ) {
      my $full_method     = "${caller}::${method}";
      *{_glob_for $full_method} = $code;
   }
}

}
1;
# ###########################################################################
# End Mo package
# ###########################################################################
