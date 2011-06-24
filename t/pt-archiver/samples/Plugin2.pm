package Plugin2;

sub new {
   my ( $class, %args ) = @_;
   return bless(\%args, $class);
}

sub is_archivable {1} # Always yes
sub before_delete {} # Take no action
sub before_insert {} # Take no action
sub before_begin {} # Take no action
sub after_finish {} # Take no action

1;

