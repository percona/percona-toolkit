package Lmo::Utils;
use strict;
use warnings qw( FATAL all );
require Exporter;
our (@ISA, @EXPORT, @EXPORT_OK);

BEGIN {
   @ISA = qw(Exporter);
   @EXPORT = @EXPORT_OK = qw(_install_coderef _unimport_coderefs _glob_for _stash_for);
}

{
   # Gets the glob from a given string.
   no strict 'refs';
   sub _glob_for {
      return \*{shift()}
   }

   # Gets the stash from a given string.
   # A stash is a symbol table hash; rough explanation on
   # http://perldoc.perl.org/perlguts.html#Stashes-and-Globs
   # But the gist of it is that we can use a hash-like thing to
   # refer to a class and modify it.
   sub _stash_for {
      return \%{ shift() . "::" };
   }
}

sub _install_coderef {
   my ($to, $code) = @_;

   return *{ _glob_for $to } = $code;
}

sub _unimport_coderefs {
   my ($target, @names) = @_;
   return unless @names;
   my $stash = _stash_for($target);
   foreach my $name (@names) {
      if ($stash->{$name} and defined(&{$stash->{$name}})) {
         delete $stash->{$name};
      }
   }
}

1;
