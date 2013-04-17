{
package JSONReportFormatter;
use Lmo;

use List::Util   qw(sum);
use Transformers qw(make_checksum parse_timestamp);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

my $have_json = eval { require JSON };

our $pretty_json = 0;
our $sorted_json = 0;

extends qw(QueryReportFormatter);

has _json => (
   is       => 'ro',
   init_arg => undef,
   builder  => '_build_json',
);

sub _build_json {
   return unless $have_json;
   return JSON->new->utf8
                   ->pretty($pretty_json)
                   ->canonical($sorted_json);
}

sub encode_json {
   my ($self, $encode) = @_;
   if ( my $json = $self->_json ) {
      return $json->encode($encode);
   }
   else {
      return Transformers::encode_json($encode);
   }
}

override [qw(rusage date hostname files header profile prepared)] => sub {
   return;
};

override event_report => sub {
   my ($self, %args) = @_;
   return $self->event_report_values(%args);
};

override query_report => sub {
   my ($self, %args) = @_;
   foreach my $arg ( qw(ea worst orderby groupby) ) {
      die "I need a $arg argument" unless defined $arg;
   }

   my $ea    = $args{ea};
   my $worst = $args{worst};

   my @attribs = @{$ea->get_attributes()};

   my %string_args = map { $_ => 1 } qw( db host arg user bytes pos_in_log );
   
   my @queries;
   foreach my $worst_info ( @$worst ) {
      my $item   = $worst_info->[0];
      my $stats  = $ea->results->{classes}->{$item};
      my $sample = $ea->results->{samples}->{$item};

      my $all_log_pos = $ea->{result_classes}->{$item}->{pos_in_log}->{all};
      my $times_seen  = sum values %$all_log_pos;
      
      my %class = (
         sample      => $sample->{arg},
         fingerprint => $item,
         checksum    => make_checksum($item),
         cnt         => $times_seen,
      );
      
      my %metrics;
      foreach my $attrib ( @attribs ) {
         $metrics{$attrib} = $ea->metrics(
            attrib => $attrib,
            where  => $item,
         );
      }

      foreach my $attrib ( keys %metrics ) {
         if ( ! grep { $_ } values %{$metrics{$attrib}} ) {
            delete $metrics{$attrib};
            next;
         }

         if ($attrib eq 'ts') {
            my $ts = delete $metrics{ts};
            foreach my $thing ( qw(min max) ) {
               next unless defined $ts && defined $ts->{$thing};
               $ts->{$thing} = parse_timestamp($ts->{$thing});
            }
            $class{ts_min} = $ts->{min};
            $class{ts_max} = $ts->{max};
         }
         elsif ( $string_args{$attrib} ) {
            $metrics{$attrib} = { value => $metrics{$attrib}{max} }; 
         }
         elsif ( ($ea->{type_for}->{$attrib} || '') eq 'num' ) {
            # Avoid scientific notation in the metrics by forcing it to use
            # six decimal places.
            for my $value ( values %{$metrics{$attrib}} ) {
               next unless $value;
               $value = sprintf '%.6f', $value;
            }
            # ..except for the percentage, which only needs two
            if ( my $pct = $metrics{$attrib}->{pct} ) {
               $metrics{$attrib}->{pct} = sprintf('%.2f', $pct);
            }
         }
      }
      push @queries, {
         class       => \%class,
         attributes  => \%metrics,
      };
   }

   my $json = $self->encode_json(\@queries);
   $json .= "\n" if $json !~ /\n\Z/;
   return $json . "\n";
};

no Lmo;
1;
}
