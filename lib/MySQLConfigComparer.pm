# This program is copyright 2010-2011 Percona Ireland Ltd.
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
# MySQLConfigComparer package
# ###########################################################################
{
# Package: MySQLConfigComparer
# MySQLConfigComparer compares and diffs C<MySQLConfig> objects. 
package MySQLConfigComparer;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# Alternate values because a config file can have var=ON and then be shown
# in SHOW VARS as var=TRUE.  I.e. there's several synonyms for basic
# true (1) and false (0), so we normalize them to make comparisons easier.
my %alt_val_for = (
   ON    => 1,
   YES   => 1,
   TRUE  => 1,
   OFF   => 0,
   NO    => 0,
   FALSE => 0,
);

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Optional Arguments:
#   ignore_variables            - Arrayref of variables to ignore
#   numeric_variables           - Arrayref of variables to compare numerically
#   optional_value_variables    - Arrayref of vars whose val is optional 
#   any_value_is_true_variables - Arrayref of vars... see below
#   base_path                   - Hashref of variable=>base_path
#
# Returns:
#   MySQLConfigComparer object
sub new {
   my ( $class, %args ) = @_;

   # These vars don't interest us so we ignore them.
   my %ignore_vars = (
      date_format      => 1,
      datetime_format  => 1,
      ft_stopword_file => 1,
      timestamp        => 1,
      time_format      => 1,
      ($args{ignore_variables}
         ? map { $_ => 1 } @{$args{ignore_variables}}
         : ()),
   );

   # The vars should be compared with == instead of eq so that
   # 0 equals 0.0, etc.
   my %is_numeric = (
      long_query_time => 1, 
      ($args{numeric_variables}
         ? map { $_ => 1 } @{$args{numeric_variables}}
         : ()),
   );

   # These vars can be specified like --log-error or --log-error=file in config
   # files.  If specified without a value, then they're "equal" to whatever
   # default value SHOW VARIABLES lists.
   my %value_is_optional = (
      log_error => 1,
      log_isam  => 1,
      ($args{optional_value_variables}
         ? map { $_ => 1 } @{$args{optional_value_variables}}
         : ()),
   ); 

   # Like value_is_optional but SHOW VARIABlES does not list a default value,
   # it only lists ON if the variable was given in a config file without or
   # without a value (e.g. --log or --log=file).  So any value from the config
   # file that's true (i.e. not a blank string) equals ON from SHOW VARIABLES.
   my %any_value_is_true = (
      log              => 1,
      log_bin          => 1,
      log_slow_queries => 1,
      ($args{any_value_is_true_variables}
         ? map { $_ => 1 } @{$args{any_value_is_true_variables}}
         : ()),
   );

   # The value of these vars are relative to some base path.  In config files
   # just a filename can be given, but in SHOW VARS the full /base/path/filename
   # is shown.  So we have to qualify the config value with the correct
   # base path.
   my %base_path = (
      character_sets_dir   => 'basedir',
      datadir              => 'basedir',
      general_log_file     => 'datadir',
      language             => 'basedir',
      log_error            => 'datadir',
      pid_file             => 'datadir',
      plugin_dir           => 'basedir',
      slow_query_log_file  => 'datadir',
      socket               => 'datadir',
      ($args{base_paths}
         ? map { $_ => 1 } @{$args{base_paths}}
         : ()),
   );

   my $self = {
      ignore_vars       => \%ignore_vars,
      is_numeric        => \%is_numeric,
      value_is_optional => \%value_is_optional,
      any_value_is_true => \%any_value_is_true,
      base_path         => \%base_path,
      ignore_case       => exists $args{ignore_case}
                                ? $args{ignore_case}
                                : 1,
   };

   return bless $self, $class;
}

# Sub: diff
#   Diff the variable values of <MySQLConfig> objects.  Only the common
#   set of variables (i.e. the vars that all configs have) are compared.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   configs - Arrayref of <MySQLConfig> objects
#
# Returns:
#   Hashref of variables that have different values, like
#   (start code)
#   {
#     max_connections => [ 100, 50 ]
#   }
#   (end code)
#   The arrayref vals correspond to the C<MySQLConfig> objects, so
#   $diff->{var}->[N] is $configs->[N]->value_of(var).
sub diff {
   my ( $self, %args ) = @_;
   my @required_args = qw(configs);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($configs) = @args{@required_args};

   if ( @$configs < 2 ) {
      PTDEBUG && _d("Less than two MySQLConfig objects; nothing to compare");
      return;
   }

   my $base_path         = $self->{base_path};
   my $is_numeric        = $self->{is_numeric};
   my $any_value_is_true = $self->{any_value_is_true};
   my $value_is_optional = $self->{value_is_optional};

   # Get the vars that exist in all configs  minus the ones we want to ignore.
   my $config0     = $configs->[0];
   my $last_config = @$configs - 1;
   my $vars        = $self->_get_shared_vars(%args);
   my $ignore_case = $self->{ignore_case};

   # Compare variables from first config (config0) to other configs (configN).
   my $diffs;
   VARIABLE:
   foreach my $var ( @$vars ) {
      my $is_dir = $var =~ m/dir$/ || $var eq 'language';
      my $val0   = $self->_normalize_value(  # config0 value
         value        => $config0->value_of($var),
         is_directory => $is_dir,
         base_path    => $config0->value_of($base_path->{$var}) || "",
      );

      eval {
         CONFIG:
         foreach my $configN ( @$configs[1..$last_config] ) {
            my $valN = $self->_normalize_value(  # configN value
               value        => $configN->value_of($var),
               is_directory => $is_dir,
               base_path    => $configN->value_of($base_path->{$var}) || "",
            );

            if ( $is_numeric->{$var} ) {
               next CONFIG if $val0 == $valN;
            }
            else {
               next CONFIG if $ignore_case
                              ? lc($val0) eq lc($valN)
                              : $val0 eq $valN;

               # Special rules apply when comparing different inputs/formats,
               # e.g. when comparing an option file to SHOW VARIABLES.  This
               # is because certain difference are actually equal in different
               # formats.
               if ( $config0->format() ne $configN->format() ) {
                  if ( $any_value_is_true->{$var} ) {
                     next CONFIG if $val0 && $valN;
                  }
                  if ( $value_is_optional->{$var} ) {
                     next CONFIG if (!$val0 && $valN) || ($val0 && !$valN);
                  }
               }
            }

            # We reach here if no comparison above was true and skipped
            # to the next CONFIG.  So reaching here means the values are
            # different.  We save the real, not-normalized values.
            PTDEBUG && _d("Different", $var, "values:", $val0, $valN);
            $diffs->{$var} = [ map { $_->value_of($var) } @$configs ];
            last CONFIG;
         }  # CONFIG
      };
      if ( $EVAL_ERROR ) {
         my $vals = join(', ',
            map {
               my $val = $_->value_of($var);
               defined $val ? $val : 'undef'
            } @$configs);
         warn "Comparing $var values ($vals) caused an error: $EVAL_ERROR";
      }
   }  # VARIABLE

   return $diffs;
}

# Sub: missing
#   Return variables that aren't in all the given <MySQLConfig> objects.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   configs - Arrayref of C<MySQLConfig> objects
#
# Returns:
#   Hashref of missing variables like,
#   (start code)
#   {
#     query_cache_size => [0, 1]
#   }
#   (end code)
#   The arrayref vals correspond to the C<MySQLConfig> objects, so
#   $missing->{var}->[N] is $configs->[N]; the values are boolean:
#   1 means the C<MySQLConfig> obj has the variable, 0 means it doesn't.
sub missing {
   my ( $self, %args ) = @_;
   my @required_args = qw(configs);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($configs) = @args{@required_args};

   if ( @$configs < 2 ) {
      PTDEBUG && _d("Less than two MySQLConfig objects; nothing to compare");
      return;
   }

   # Get a unique list of all vars from all configs.
   my %vars = map { $_ => 1 } map { keys %{$_->variables()} } @$configs;
   my $missing;
   foreach my $var ( keys %vars ) {
      # If the number of configs having the var is less than the number of
      # configs, then one of the configs must be missing the variable.
      my $n_configs_having_var = grep { $_->has($var) } @$configs;
      if ( $n_configs_having_var < @$configs ) {
         $missing->{$var} = [ map { $_->has($var) ? 1 : 0 } @$configs ];
      }
   }

   return $missing;
}

sub _normalize_value {
   my ( $self, %args ) = @_;
   my ($val, $is_dir, $base_path) = @args{qw(value is_directory base_path)};

   $val = defined $val ? $val : '';
   $val = $alt_val_for{$val} if exists $alt_val_for{$val};

   if ( $val ) {
      if ( $is_dir ) {
         $val .= '/' unless $val =~ m/\/$/;
      }
      if ( $base_path && $val !~ m/^\// ) {
         $val =~ s/^\.?(.+)/$base_path\/$1/;  # prepend base path
         $val =~ s/\/{2,}/\//g;               # make redundant // single /
      }
   }
   return $val;
}

sub _get_shared_vars {
   my ( $self, %args ) = @_;
   my ($configs)   = @args{qw(configs)};
   my $ignore_vars = $self->{ignore_vars};
   my $config0     = $configs->[0];
   my $last_config = @$configs - 1;
   my @vars
      = grep { !$ignore_vars->{$_} }
      map {
         my $config = $_;
         my $vars   = $config->variables();
         grep { $config0->has($_); } keys %$vars;
      }  @$configs[1..$last_config];
   return \@vars;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End MySQLConfigComparer package
# ###########################################################################
