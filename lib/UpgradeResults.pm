# This program is copyright 2013 Percona Ireland Ltd.
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
# UpgradeResults package
# ###########################################################################
{
package UpgradeResults;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
use Digest::MD5 qw(md5_hex);

use Lmo;

has 'max_class_size' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has 'max_examples' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has 'classes' => (
    is       => 'rw',
    isa      => 'HashRef',
    required => 0,
    default  => sub { return {} },
);

sub save_diffs {
   my ($self, %args) = @_;

   my $event            = $args{event};
   my $query_time_diffs = $args{query_time_diffs};
   my $warning_diffs    = $args{warning_diffs};
   my $row_diffs        = $args{row_diffs};

   my $class = $self->class(event => $event);

   if ( my $query = $self->_can_save(event => $event, class => $class) ) {
      if ( $query_time_diffs
           && scalar @{$class->{query_time_diffs}} < $self->max_examples ) {
         push @{$class->{query_time_diffs}}, [
            $query,
            $query_time_diffs,
         ];
      }

      if ( $warning_diffs && @$warning_diffs
           && scalar @{$class->{warning_diffs}} < $self->max_examples ) {
         push @{$class->{warning_diffs}}, [
            $query,
            $warning_diffs,
         ];
      }

      if ( $row_diffs && @$row_diffs
           && scalar @{$class->{row_diffs}} < $self->max_examples ) {
         push @{$class->{row_diffs}}, [
            $query,
            $row_diffs,
         ];
      }
   }

   $self->report_if_ready(class => $class);

   return;
}

sub save_error {
   my ($self, %args) = @_;

   my $event  = $args{event};
   my $error1 = $args{error1};
   my $error2 = $args{error2};

   my $class = $self->class(event => $event);

   if ( my $query = $self->_can_save(event => $event, class => $class) ) {
      if ( scalar @{$class->{errors}} < $self->max_examples ) {
         push @{$class->{errors}}, [
            $query,
            $error1,
            $error2,
         ];
      }
   }

   $self->report_if_ready(class => $class);

   return;
}

sub save_failed_query {
   my ($self, %args) = @_;

   my $event  = $args{event};
   my $error1 = $args{error1};
   my $error2 = $args{error2};

   my $class = $self->class(event => $event);

   if ( my $query = $self->_can_save(event => $event, class => $class) ) {
      if ( scalar @{$class->{failures}} < $self->max_examples ) {
         push @{$class->{failures}}, [
            $query,
            $error1,
            $error2,
         ];
      }
   }

   $self->report_if_ready(class => $class);

   return;
}

sub _can_save {
   my ($self, %args) = @_;
   my $event = $args{event};
   my $class = $args{class};
   my $query = $event->{arg};
   if ( $class->{reported} ) {
      PTDEBUG && _d('Class already reported');
      return;
   }
   $class->{total_queries}++;
   if ( exists $class->{unique_queries}->{$query}
        || scalar keys %{$class->{unique_queries}} < $self->max_class_size ) {
      $class->{unique_queries}->{$query}++;
      return $query;
   }
   PTDEBUG && _d('Too many queries in class, discarding', $query);
   $class->{discarded}++;
   return;
}

sub class {
   my ($self, %args) = @_;
   my $event = $args{event};

   my $id      = uc(substr(md5_hex($event->{fingerprint}), -16));
   my $classes = $self->classes;
   my $class   = $classes->{$id};
   if ( !$class ) {
      $class = $self->_new_class(
         id    => $id,
         event => $event,
      );
      $classes->{$id} = $class;
   }
   return $class;
}

sub _new_class {
   my ($self, %args) = @_;
   my $id    = $args{id};
   my $event = $args{event};
   PTDEBUG && _d('New query class:', $id, $event->{fingerprint});
   my $class = {
      id               => $id,
      fingerprint      => $event->{fingerprint},
      discarded        => 0,
      unique_queries   => {
         $event->{arg} => 0,
      },
      failures         => [],  # error on both hosts
      errors           => [],  # error on one host
      query_time_diffs => [],
      warning_diffs    => [],
      row_diffs        => [],
   };
   return $class;
}

sub report_unreported_classes {
   my ($self) = @_;
   my $success = 1;
   my $classes = $self->classes;
   foreach my $id ( sort keys %$classes ) {
      eval {
         my $class = $classes->{$id};
         my $reason;
         if ( !scalar @{$class->{failures}} ) {
            $reason = 'it has diffs';
         }
         elsif (    scalar @{$class->{errors}}
                 || scalar @{$class->{query_time_diffs}}
                 || scalar @{$class->{warning_diffs}}
                 || scalar @{$class->{row_diffs}} ) {
            $reason = 'it has SQL errors and diffs';
         }
         else {
            $reason = 'it has SQL errors'
         }
         $self->report_class(
            class   => $class,
            reasons => ["$reason, but hasn't been reported yet"],
         );
         $class->{reported} = 1; 
      };
      if ( $EVAL_ERROR ) {
         $success = 1;
         warn Dumper($classes->{$id});
         warn "Error reporting query class $id: $EVAL_ERROR";
      }
   }
   return $success;
}

sub report_if_ready {
   my ($self, %args) = @_;
   my $class = $args{class};
   my $max_examples   = $self->max_examples;
   my $max_class_size = $self->max_class_size;
   my @report_reasons;

   if ( scalar keys %{$class->{unique_queries}} >= $max_class_size ) {
      push @report_reasons, "it's full (--max-class-size)";
   }

   if ( scalar @{$class->{query_time_diffs}} >= $max_examples ) {
      push @report_reasons, "there are $max_examples query diffs";
   }

   if ( scalar @{$class->{warning_diffs}} >= $max_examples ) {
      push @report_reasons, "there are $max_examples warning diffs";
   }

   if ( scalar @{$class->{row_diffs}} >= $max_examples ) {
      push @report_reasons, "there are $max_examples row diffs";
   }

   if ( scalar @{$class->{errors}} >= $max_examples ) {
      push @report_reasons, "there are $max_examples query errors";
   }

   if ( scalar @{$class->{failures}} >= $max_examples ) {
      push @report_reasons, "there are $max_examples failed queries";
   }

   if ( scalar @report_reasons ) {
      PTDEBUG && _d('Reporting class because', @report_reasons);
      $self->report_class(
         class   => $class,
         reasons => \@report_reasons,
      );
      $class->{reported} = 1; 
   }

   return;
}

sub report_class {
   my ($self, %args) = @_;
   my $class   = $args{class};
   my $reasons = $args{reasons};

   if ( $class->{reported} ) {
      PTDEBUG && _d('Class already reported');
      return;
   }

   PTDEBUG && _d('Reporting class', $class->{id}, $class->{fingerprint});

   $self->_print_class_header(
      class   => $class,
      reasons => $reasons,
   );

   if ( scalar @{$class->{failures}} ) {
      $self->_print_failures(
         failures => $class->{failures},
      );
   }

   if ( scalar @{$class->{errors}} ) {
      $self->_print_errors(
         errors => $class->{errors},
      );
   }

   if ( scalar @{$class->{query_time_diffs}} ) {
      $self->_print_diffs(
         diffs     => $class->{query_time_diffs},
         name      => 'Query time',
         formatter => \&_format_query_times,
      );
   }

   if ( scalar @{$class->{warning_diffs}} ) {
      $self->_print_diffs(
         diffs     => $class->{warning_diffs},
         name      => 'Warning',
         formatter => \&_format_warnings,
      );
   }

   if ( scalar @{$class->{row_diffs}} ) {
      $self->_print_diffs(
         diffs     => $class->{row_diffs},
         name      => 'Row',
         formatter => \&_format_rows,
      );
   }

   return;
}

# This is a terrible hack due to two things: 1) our own util/update-modules
# things lines starting with multiple # are package headers; 2) the same
# util strips all comment lines start with #.  So if we use the literal #
# for this header, util/update-modules will remove them from the code.
# *facepalm*
my $class_header_format = <<'EOF';

%s
%s
%s

Reporting class because %s.

Total queries      %s
Unique queries     %s
Discarded queries  %s

%s
EOF

sub _print_class_header {
   my ($self, %args) = @_;
   my $class   = $args{class};
   my @reasons = @{ $args{reasons} };

   my $unique_queries = do {
      my $i = 0;
      map { $i += $_ } values %{$class->{unique_queries}};
      $i;
   };
   PTDEBUG && _d('Unique queries:', $unique_queries);

   my $reasons;
   if ( scalar @reasons > 1 ) {
      $reasons = join(', ', @reasons[0..($#reasons - 1)])
               . ', and ' . $reasons[-1];
   }
   else {
      $reasons = $reasons[0];
   }
   PTDEBUG && _d('Reasons:', $reasons);

   printf $class_header_format,
      ('#' x 72),
      ('# Query class ' . ($class->{id} || '?')),
      ('#' x 72),
      ($reasons                || '?'),
      (defined $class->{total_queries} ? $class->{total_queries} : '?'),
      (defined $unique_queries         ? $unique_queries         : '?'),
      (defined $class->{discarded}     ? $class->{discarded}     : '?'),
      ($class->{fingerprint}   || '?');

   return;
}

sub _print_diff_header {
   my ($self, %args) = @_;
   my $name  = $args{name}  || '?';
   my $count = $args{count} || '?';
   print "\n##\n## $name diffs: $count\n##\n";
   return;
}

sub _print_failures {
   my ($self, %args) = @_;
   my $failures = $args{failures};

   my $n_failures = scalar @$failures;

   print "\n##\n## SQL errors: $n_failures\n##\n";

   my $failno = 1;
   foreach my $failure ( @$failures ) {
      print "\n-- $failno.\n";
      if ( ($failure->[1] || '') eq ($failure->[2] || '') ) {
         printf "\nOn both hosts:\n\n" . ($failure->[1] || '') . "\n";
      }
      else {
         printf "\n%s\n\nvs.\n\n%s\n",
            ($failure->[1] || ''),
            ($failure->[2] || '');
      }
      print "\n" . ($failure->[0] || '?') . "\n";
      $failno++;
   }

   return;
}

sub _print_errors {
   my ($self, %args) = @_;
   my $errors = $args{errors};

   $self->_print_diff_header(
      name  => 'Query errors',
      count => scalar @$errors,
   );

   my $fmt = "\n%s\n\nvs.\n\n%s\n";

   my $errorno = 1;
   foreach my $error ( @$errors ) {
      print "\n-- $errorno.\n";
      printf $fmt,
         ($error->[1] || 'No error'),
         ($error->[2] || 'No error');
      print "\n" . ($error->[0] || '?') . "\n";
      $errorno++;
   }

   return;
}

sub _print_diffs {
   my ($self, %args) = @_;
   my $diffs     = $args{diffs};
   my $name      = $args{name};
   my $formatter = $args{formatter};

   $self->_print_diff_header(
      name  => $name,
      count => scalar @$diffs,
   );

   my $diffno = 1;
   foreach my $diff ( @$diffs ) {
      my $query     = $diff->[0];
      my $diff_vals = $diff->[1];
      print "\n-- $diffno.\n";
      my $formatted_diff_vals = $formatter->($diff_vals);
      print $formatted_diff_vals || '?';
      print "\n" . ($query || '?') . "\n";
      $diffno++;
   }

   return;
}

my $warning_format = <<'EOL';
   Code: %s
  Level: %s
Message: %s
EOL

sub _format_warnings {
   my ($warnings) = @_;
   return unless $warnings && @$warnings;
   my @warnings;
   foreach my $warn ( @$warnings ) {
      my $code  = $warn->[0];
      my $warn1 = $warn->[1];
      my $warn2 = $warn->[2];
      my $host1_warn
         = $warn1 ? sprintf $warning_format, 
                       ($warn1->{Code}    || $warn1->{code}    || '?'),
                       ($warn1->{Level}   || $warn1->{level}   || '?'),
                       ($warn1->{Message} || $warn1->{message} || '?')
         :          "No warning $code\n";
      my $host2_warn
         = $warn2 ? sprintf $warning_format, 
                       ($warn2->{Code}    || $warn2->{code}    || '?'),
                       ($warn2->{Level}   || $warn2->{level}   || '?'),
                       ($warn2->{Message} || $warn2->{message} || '?')
         :          "No warning $code\n";

      my $warning = sprintf "\n%s\nvs.\n\n%s", $host1_warn, $host2_warn;
      push @warnings, $warning;
   }
   return join("\n\n", @warnings);
}

sub _format_rows {
   my ($rows) = @_;
   return unless $rows && @$rows;
   my @diffs;
   foreach my $row ( @$rows ) {
      if ( !defined $row->[1] || !defined $row->[2] ) {
         # missing rows
         my $n_missing_rows = $row->[0];
         my $missing_rows   = $row->[1] || $row->[2];
         my $dir            = !defined $row->[1] ? '>' : '<';
         my $diff
            = '@ first ' . scalar @$missing_rows
            . ' of ' . ($n_missing_rows || '?') . " missing rows\n";
         foreach my $row ( @$missing_rows ) {
            $diff .= "$dir "
                   . join(',', map {defined $_ ? $_ : 'NULL'} @$row) . "\n";
         }
         push @diffs, $diff;
      }
      else {
         # diff rows
         my $rowno = $row->[0];
         my $cols1 = $row->[1];
         my $cols2 = $row->[2];
         my $diff
            = "@ row " . ($rowno || '?') . "\n"
            . '< ' . join(',', map {defined $_ ? $_ : 'NULL'} @$cols1) . "\n"
            . '> ' . join(',', map {defined $_ ? $_ : 'NULL'} @$cols2) . "\n";
         push @diffs, $diff;
      }
   }
   return "\n" . join("\n", @diffs);
}

sub _format_query_times {
   my ($query_times) = @_;
   return unless $query_times;
   my $fmt = "\n%s vs. %s seconds (%sx increase)\n";
   my $diff = sprintf $fmt,
      ($query_times->[0] || '?'),
      ($query_times->[1] || '?'),
      ($query_times->[2] || '?');
   return $diff;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

no Lmo;
1;
}
# ###########################################################################
# End UpgradeResults package
# ###########################################################################
