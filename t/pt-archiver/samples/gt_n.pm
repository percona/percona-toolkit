package gt_n;

use strict;
use English qw(-no_match_vars);
use constant MKDEBUG  => $ENV{MKDEBUG};
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;


# Changes these two values for your table.
use constant MAX_ROWS => 5;
use constant WHERE    => 'status="ok"';


sub new {
   my ( $class, %args ) = @_;

   my $sql = "SELECT COUNT(*) FROM $args{db}.$args{tbl} WHERE " . WHERE;
   MKDEBUG && _d('Row count sql:', $sql);
   my $sth = $args{dbh}->prepare($sql);

   my $self = {
      %args,
      row_count_sth => $sth,
      done          => 0,
   };
   return bless $self, $class;
}

# Executes $self->{row_count_sth} and returns the number of rows.
sub get_row_count {
   my ( $self ) = @_;
   my $sth = $self->{row_count_sth};
   $sth->execute();
   my @row = $sth->fetchrow_array();
   MKDEBUG && _d('Row count:', $row[0]);
   $sth->finish();
   return $row[0];
}

sub before_begin {
   my ( $self, %args ) = @_;
   MKDEBUG && _d('before begin');
   # We don't need to do anything here.
   return;
}

sub is_archivable {
   my ( $self, %args ) = @_;
   MKDEBUG && _d('is archivable');

   if ( $self->{done} ) {
      MKDEBUG && _d("Already done, skipping row count");
      return 0;
   }

   my $n_rows = $self->get_row_count();
   if ( $n_rows <= MAX_ROWS ) {
      MKDEBUG && _d('Done archiving, row count <', MAX_ROWS,
         '; first non-archived row:', Dumper($args{row}));
      $self->{done} = 1;
      return 0;
   }

   return 1;  # Archive the row.
}

sub before_delete {
   my ( $self, %args ) = @_;
   # We don't need to do anything here.
   return;
}

sub after_finish {
   my ( $self ) = @_;
   MKDEBUG && _d('after finish');
   # Just to show in debug output how many rows are left at the end.
   my $n_rows = $self->get_row_count();
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

