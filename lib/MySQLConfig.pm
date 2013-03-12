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
# MySQLConfig package
# ###########################################################################
{
# Package: MySQLConfig
# MySQLConfig parses and encapsulates system variables and values from
# SHOW VARIABLES, option files, mysqld --help --verbose or my_print_defaults.
# A MySQLConfig object represents how MySQL is or would be configured given
# one of those inputs.  If the input is SHOW VARIABLES, then the config is
# acive, i.e. MySQL's running config.  All other inputs are inactive, i.e.
# how MySQL should or would be running if started with the config.
#
# Inactive configs are made to mimic SHOW VARIABLES so that MySQLConfig
# objects can be reliably compared with MySQLConfigComparer.  This is
# necessary because the inputs are different in how they list values,
# how they treat variables with optional values, etc.
#
# Only variables present in the input are saved in the MySQLConfig object.
# So if <has()> returns false, then the variable did not appear in the input.
package MySQLConfig;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

my %can_be_duplicate = (
   replicate_wild_do_table     => 1,
   replicate_wild_ignore_table => 1,
   replicate_rewrite_db        => 1,
   replicate_ignore_table      => 1,
   replicate_ignore_db         => 1,
   replicate_do_table          => 1,
   replicate_do_db             => 1,
);

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Arguments:
#   file       - Filename of an option file, or containing output of
#                mysqld --help --verbose, my_print_defaults or SHOW VARIABLES
#   output     - Text output of one of ^ if you want to slurp the file manually
#   result_set - Arrayref of SHOW VARIABLES
#   dbh        - dbh to get SHOW VARIABLES from
#   TextResultSetParser - <TextResultSetParser> object if file or output
#                         arg is given
#
# Returns:
#   MySQLConfig object
sub new {
   my ( $class, %args ) = @_;
   my @requires_one_of = qw(file output result_set dbh);
   my $required_arg    = grep { $args{$_} } @requires_one_of;
   if ( !$required_arg ) {
      die "I need a " . join(', ', @requires_one_of[0..$#requires_one_of-1])
         . " or " . $requires_one_of[-1] . " argument";
   }
   if ( $required_arg > 1 ) {
      die "Specify only one "
         . join(', ', @requires_one_of[0..$#requires_one_of-1])
         . " or " . $requires_one_of[-1] . " argument";
   }
   if ( $args{file} || $args{output} ) {
      die "I need a TextResultSetParser argument"
         unless $args{TextResultSetParser};
   }

   if ( $args{file} ) {
      $args{output} = _slurp_file($args{file});
   }

   my %config_data = _parse_config(%args);

   my $self = {
      %args,
      %config_data,
   };

   return bless $self, $class;
}

sub _parse_config {
   my ( %args ) = @_;

   my %config_data;
   if ( $args{output} ) {
      %config_data = _parse_config_output(%args);
   }
   elsif ( my $rows = $args{result_set} ) {
      $config_data{format} = $args{format} || 'show_variables';
      $config_data{vars}   = { map { @$_ } @$rows };
   }
   elsif ( my $dbh = $args{dbh} ) {
      $config_data{format} = $args{format} || 'show_variables';
      my $sql = "SHOW /*!40103 GLOBAL*/ VARIABLES";
      PTDEBUG && _d($dbh, $sql);
      my $rows = $dbh->selectall_arrayref($sql);
      $config_data{vars} = { map { @$_ } @$rows };
      $config_data{mysql_version} = _get_version($dbh);
   }
   else {
      die "Unknown config source";
   }

   handle_special_vars(\%config_data);
   
   return %config_data;
}

sub handle_special_vars {
   my ($config_data) = @_;
   
   if ( $config_data->{vars}->{wsrep_provider_options} ) {
      my $vars  = $config_data->{vars};
      my $dupes = $config_data->{duplicate_vars};
      for my $wpo ( $vars->{wsrep_provider_options}, @{$dupes->{wsrep_provider_options} || [] } ) {
         my %opts = $wpo =~ /(\S+)\s*=\s*(\S*)(?:;|;?$)/g;
         while ( my ($var, $val) = each %opts ) {
            $val =~ s/;$//;
            if ( exists $vars->{$var} ) {
               push @{$dupes->{$var} ||= []}, $val;
            }
            $vars->{$var} = $val;
         }
      }
      # Delete from vars, but not from dupes, since we still want that
      delete $vars->{wsrep_provider_options};
   }

   return;
}

sub _parse_config_output {
   my ( %args ) = @_;
   my @required_args = qw(output TextResultSetParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($output) = @args{@required_args};
   PTDEBUG && _d("Parsing config output");

   my $format = $args{format} || detect_config_output_format(%args);
   if ( !$format ) {
      die "Cannot auto-detect the MySQL config format";
   }

   my $vars;      # variables hashref
   my $dupes;     # duplicate vars hashref
   my $opt_files; # option files arrayref
   if ( $format eq 'show_variables' ) {
      $vars = parse_show_variables(%args);
   }
   elsif ( $format eq 'mysqld' ) {
      ($vars, $opt_files) = parse_mysqld(%args);
   }
   elsif ( $format eq 'my_print_defaults' ) {
      ($vars, $dupes) = parse_my_print_defaults(%args);
   }
   elsif ( $format eq 'option_file' ) {
      ($vars, $dupes) = parse_option_file(%args);
   }
   else {
      die "Invalid MySQL config format: $format";
   }

   die "Failed to parse MySQL config" unless $vars && keys %$vars;

   if ( $format ne 'show_variables' ) {
      _mimic_show_variables(
         %args,
         format => $format,
         vars   => $vars,
      );
   }
   
   return (
      format         => $format,
      vars           => $vars,
      option_files   => $opt_files,
      duplicate_vars => $dupes,
   );
}

sub detect_config_output_format {
   my ( %args ) = @_;
   my @required_args = qw(output);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($output) = @args{@required_args};

   my $format;
   if (    $output =~ m/\|\s+\w+\s+\|\s+.+?\|/
        || $output =~ m/\*+ \d/
        || $output =~ m/Variable_name:\s+\w+/
        || $output =~ m/Variable_name\s+Value$/m )
   {
      PTDEBUG && _d('show variables format');
      $format = 'show_variables';
   }
   elsif (    $output =~ m/Starts the MySQL database server/
           || $output =~ m/Default options are read from /
           || $output =~ m/^help\s+TRUE /m )
   {
      PTDEBUG && _d('mysqld format');
      $format = 'mysqld';
   }
   elsif ( $output =~ m/^--\w+/m ) {
      PTDEBUG && _d('my_print_defaults format');
      $format = 'my_print_defaults';
   }
   elsif ( $output =~ m/^\s*\[[a-zA-Z]+\]\s*$/m ) {
      PTDEBUG && _d('option file format');
      $format = 'option_file',
   }

   return $format;
}

sub parse_show_variables {
   my ( %args ) = @_;
   my @required_args = qw(output TextResultSetParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($output, $trp) = @args{@required_args};

   my %config = map {
      $_->{Variable_name} => $_->{Value}
   } @{ $trp->parse($output) };

   return \%config;
}

# Parse "mysqld --help --verbose" and return a hashref of variable=>values
# and an arrayref of default defaults files if possible.  The "default
# defaults files" are the defaults file that mysqld reads by default if no
# defaults file is explicitly given by --default-file.
sub parse_mysqld {
   my ( %args ) = @_;
   my @required_args = qw(output);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($output) = @args{@required_args};

   # First look for the list of option files like
   #   Default options are read from the following files in the given order:
   #   /etc/my.cnf /usr/local/mysql/etc/my.cnf ~/.my.cnf 
   my @opt_files;
   if ( $output =~ m/^Default options are read.+\n/mg ) {
      my ($opt_files) = $output =~ m/\G^(.+)\n/m;
      my %seen;
      my @opt_files = grep { !$seen{$_} } split(' ', $opt_files);
      PTDEBUG && _d('Option files:', @opt_files);
   }
   else {
      PTDEBUG && _d("mysqld help output doesn't list option files");
   }

   # The list of sys vars and their default vals begins like:
   #   Variables (--variable-name=value)
   #   and boolean options {FALSE|TRUE}  Value (after reading options)
   #   --------------------------------- -----------------------------
   #   help                              TRUE
   #   abort-slave-event-count           0
   # So we search for that line of hypens.
   #
   # It also ends with something like
   #
   #   wait_timeout                      28800
   #   
   #   To see what values a running MySQL server is using, type
   #   'mysqladmin variables' instead of 'mysqld --verbose --help'.
   #
   # So try to find it by locating a double newline, and strip it away
   if ( $output !~ m/^-+ -+$(.+?)(?:\n\n.+)?\z/sm ) {
      PTDEBUG && _d("mysqld help output doesn't list vars and vals");
      return;
   }

   # Grab the varval list.
   my $varvals = $1;

   # Parse the "var  val" lines.  2nd retval is duplicates but there
   # shouldn't be any with mysqld.
   my ($config, undef) = _parse_varvals(
      qr/^(\S+)(.*)$/,
      $varvals,
   );

   return $config, \@opt_files;
}

# Parse "my_print_defaults" output and return a hashref of variable=>values
# and a hashref of any duplicated variables.
sub parse_my_print_defaults {
   my ( %args ) = @_;
   my @required_args = qw(output);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($output) = @args{@required_args};

   # Parse the "--var=val" lines.
   my ($config, $dupes) = _parse_varvals(
      qr/^--([^=]+)(?:=(.*))?$/,
      $output,
   );

   return $config, $dupes;
}

# Parse the [mysqld] section of an option file and return a hashref of
# variable=>values and a hashref of any duplicated variables.
sub parse_option_file {
   my ( %args ) = @_;
   my @required_args = qw(output);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($output) = @args{@required_args};

   my ($mysqld_section) = $output =~ m/\[mysqld\](.+?)(?:^\s*\[\w+\]|\Z)/xms;
   die "Failed to parse the [mysqld] section" unless $mysqld_section;

   # Parse the "var=val" lines.
   my ($config, $dupes) = _parse_varvals(
      qr/^([^=]+)(?:=(.*))?$/,
      $mysqld_section,
   );

   return $config, $dupes;
}

# Called by _parse_varvals(), takes two arguments: a regex, and
# a string to match against. The string will be split in lines,
# and each line will be matched against the regex.
# The regex must return to captures, although the second doesn't
# have to match anything.
# Returns a hashref of arrayrefs ala
# { port => [ 12345, 12346 ], key_buffer_size => [ "16M" ] }
sub _preprocess_varvals {
   my ($re, $to_parse) = @_;

   my %vars;
   LINE:
   foreach my $line ( split /\n/, $to_parse ) {
      next LINE if $line =~ m/^\s*$/;   # no empty lines
      next LINE if $line =~ /^\s*[#;]/; # no # or ; comment lines

      if ( $line !~ $re ) {
         PTDEBUG && _d("Line <", $line, "> didn't match $re");
         next LINE;
      }

      my ($var, $val) = ($1, $2);
      
      # Variable names are usually specified like "log-bin"
      # but in SHOW VARIABLES they're all like "log_bin".
      $var =~ tr/-/_/;

      # Remove trailing comments
      $var =~ s/\s*#.*$//;

      if ( !defined $val ) {
         $val = '';
      }
      
      # Strip leading and trailing whitespace.
      for my $item ($var, $val) {
         $item =~ s/^\s+//;
         $item =~ s/\s+$//;
      }

      push @{$vars{$var} ||= []}, $val
   }

   return \%vars;
}

# Parses a string of variables and their values ("varvals"), returns two
# hashrefs: one with normalized variable=>value, the other with duplicate
# vars.
sub _parse_varvals {
   my ( $vars ) = _preprocess_varvals(@_);

   # Config built from parsing the given varvals.
   my %config;

   # Discover duplicate vars.  
   my %duplicates;

   while ( my ($var, $vals) = each %$vars ) {
      my $val = _process_val( pop @$vals );
      # If the variable has duplicates, then @$vals will contain
      # the rest of the values
      if ( @$vals && !$can_be_duplicate{$var} ) {
         # The var is a duplicate (in the bad sense, i.e. where user is
         # probably unaware that there's two different values for this var
         # but only the last is used).
         PTDEBUG && _d("Duplicate var:", $var);
         foreach my $current_val ( map { _process_val($_) } @$vals ) {
            push @{$duplicates{$var} ||= []}, $current_val;
         }
      }

      PTDEBUG && _d("Var:", $var, "val:", $val);

      # Save this var-val.
      $config{$var} = $val;
   }

   return \%config, \%duplicates;
}

my $quote_re = qr/
   \A             # Start of value
   (['"])         # Opening quote
   (.*)           # Value
   \1             # Closing quote
   \s*(?:\#.*)?   # End of line comment
   [\n\r]*\z      # End of value
/x;
sub _process_val {
   my ($val) = @_;

   if ( $val =~ $quote_re ) {
      # If it matches the quote re, then $2 holds the value
      $val = $2;
   }
   else {
      # Otherwise, remove possible trailing comments
      $val =~ s/\s*#.*//;
   }

   if ( my ($num, $factor) = $val =~ m/(\d+)([KMGT])b?$/i ) {
      # value is a size like 1k, 16M, etc.
      my %factor_for = (
         k => 1_024,
         m => 1_048_576,
         g => 1_073_741_824,
         t => 1_099_511_627_776,
      );
      $val = $num * $factor_for{lc $factor};
   }
   elsif ( $val =~ m/No default/ ) {
      $val = '';
   }
   return $val;
}

# Sub: _mimic_show_variables
#   Make the variables' values mimic SHOW VARIABLES.  Different output formats
#   list values differently.  To make comparisons easier, outputs are made to
#   mimic SHOW VARIABLES.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   vars   - Hashref of variables-values
#   format - Config output format (mysqld, option_file, etc.)
sub _mimic_show_variables {
   my ( %args ) = @_;
   my @required_args = qw(vars format);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($vars, $format) = @args{@required_args};
   
   foreach my $var ( keys %$vars ) {
      if ( $vars->{$var} eq '' ) {
         if ( $format eq 'mysqld' ) {
            # mysqld lists "(No default value)" for certain variables
            # that are not set/configured.  _parse_varvals() turns this
            # into a blank string.  For most vars this means there's no
            # value and SHOW VARIABLES will similarly show no value.
            # But for log*, skip* and ignore* vars, SHOW VARIABLES will
            # show OFF.  But, log_error is an exception--it's practically
            # always on.
            if ( $var ne 'log_error' && $var =~ m/^(?:log|skip|ignore)/ ) {
               $vars->{$var} = 'OFF';
            }
         }
         else {
            # Output formats other than mysqld (e.g. option file), if
            # a variable is listed then it's enabled, like --skip-federated.
            # SHOW VARIBLES will show ON for these.
            $vars->{$var} = 'ON';
         }
      }
   }

   return;
}

sub _slurp_file {
   my ( $file ) = @_;
   die "I need a file argument" unless $file;
   PTDEBUG && _d("Reading", $file);
   open my $fh, '<', $file or die "Cannot open $file: $OS_ERROR";
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;
   return $contents;
}

sub _get_version {
   my ( $dbh ) = @_;
   return unless $dbh;
   my $version = $dbh->selectrow_arrayref('SELECT VERSION()')->[0];
   $version =~ s/(\d\.\d{1,2}.\d{1,2})/$1/;
   PTDEBUG && _d('MySQL version', $version);
   return $version;
}

# #############################################################################
# Accessor methods.
# #############################################################################

# Returns true if this MySQLConfig obj has the given variable.
sub has {
   my ( $self, $var ) = @_;
   return exists $self->{vars}->{$var};
}

# Return the value of the given variable.
sub value_of {
   my ( $self, $var ) = @_;
   return unless $var;
   return $self->{vars}->{$var};
}

# Return hashref of all variables.
sub variables {
   my ( $self, %args ) = @_;
   return $self->{vars};
}

# Return hashref of duplicate variables.
sub duplicate_variables {
   my ( $self ) = @_;
   return $self->{duplicate_vars};
}

# Return arrayref of option files.
sub option_files {
   my ( $self ) = @_;
   return $self->{option_files};
}

# Return MySQL version.
sub mysql_version {
   my ( $self ) = @_;
   return $self->{mysql_version};
}

# Return the config file format (mysqld, option file, etc.)
sub format {
   my ( $self ) = @_;
   return $self->{format};
}

# Return true if the config is active (i.e. the effective config
# that MySQL is using; only true if config is from SHOW VARIABLES).
sub is_active {
   my ( $self ) = @_;
   return $self->{dbh} ? 1 : 0;
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
# End MySQLConfig package
# ###########################################################################
