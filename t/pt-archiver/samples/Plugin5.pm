package Plugin5;

sub new {
   my ( $class, %args ) = @_;
   $args{dbh}->do('create temporary table test.tmp_table(a int not null primary key)');
   $args{dbh}->do('insert into test.tmp_table values(1), (2)');
   return bless(\%args, $class);
}

sub is_archivable {1} # Always yes

sub before_delete {} # Take no action

sub before_insert { }

sub before_begin {} # Take no action
sub after_finish {} # Take no action

1;
