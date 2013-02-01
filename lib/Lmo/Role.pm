package Lmo::Role;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Lmo ();
use base qw(Role::Tiny);

use Lmo::Utils qw(_install_coderef _unimport_coderefs _stash_for);

BEGIN { *INFO = \%Role::Tiny::INFO }

our %INFO;

sub _install_tracked {
  my ($target, $name, $code) = @_;
  $INFO{$target}{exports}{$name} = $code;
  _install_coderef "${target}::${name}" => $code;
}

sub import {
  my $target = caller;
  my ($me) = @_;
   # Set warnings and strict for the caller.
   warnings->import(qw(FATAL all));
   strict->import();

=begin
  if ($Moo::MAKERS{$target} and $Moo::MAKERS{$target}{is_class}) {
    die "Cannot import Moo::Role into a Moo class";
  }
=cut
  return if $INFO{$target}; # already exported into this package
  $INFO{$target} = { is_role => 1 };
  # get symbol table reference_unimport_coderefs
  my $stash = _stash_for $target;
  
  _install_tracked $target => has => \*Lmo::has;
  
  # install before/after/around subs
  foreach my $type (qw(before after around)) {
    _install_tracked $target => $type => sub {
      require Class::Method::Modifiers;
      push @{$INFO{$target}{modifiers}||=[]}, [ $type => @_ ];
    };
  }
  
  _install_tracked $target => requires => sub {
    push @{$INFO{$target}{requires}||=[]}, @_;
  };
  
  _install_tracked $target => with => \*Lmo::with;

  # grab all *non-constant* (stash slot is not a scalarref) subs present
  # in the symbol table and store their refaddrs (no need to forcibly
  # inflate constant subs into real subs) - also add '' to here (this
  # is used later) with a map to the coderefs in case of copying or re-use
  my @not_methods = ('', map { *$_{CODE}||() } grep !ref($_), values %$stash);
  @{$INFO{$target}{not_methods}={}}{@not_methods} = @not_methods;
  # a role does itself
  $Role::Tiny::APPLIED_TO{$target} = { $target => undef };

}

sub unimport {
  my $target = caller;
  _unimport_coderefs($target, keys %{$INFO{$target}{exports}});
}

1;
