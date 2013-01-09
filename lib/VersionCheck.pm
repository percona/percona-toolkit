# This program is copyright 2012 Percona Ireland Ltd.
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
# VersionCheck package
# ###########################################################################
{
# Package: VersionCheck
# VersionCheck checks program versions with Percona.
package VersionCheck;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use File::Basename ();
use Data::Dumper ();

sub Dumper {
   local $Data::Dumper::Indent    = 1;
   local $Data::Dumper::Sortkeys  = 1;
   local $Data::Dumper::Quotekeys = 0;

   Data::Dumper::Dumper(@_);
}

sub new {
   my ($class, %args) = @_;
   my $self = {
      valid_types => qr/
         ^(?:
             os_version
            |perl_version
            |perl_module_version
            |mysql_variable
            |bin_version
         )$/x,
   };
   return bless $self, $class;
}

sub parse_server_response {
   my ($self, %args) = @_;
   my @required_args = qw(response);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($response) = @args{@required_args};

   my %items = map {
      my ($item, $type, $vars) = split(";", $_);
      if ( !defined $args{split_vars} || $args{split_vars} ) {
         $vars = [ split(",", ($vars || '')) ];
      }
      $item => {
         item => $item,
         type => $type,
         vars => $vars,
      };
   } split("\n", $response);

   PTDEBUG && _d('Items:', Dumper(\%items));

   return \%items;
}

sub get_versions {
   my ($self, %args) = @_;
   my @required_args = qw(items);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($items) = @args{@required_args};

   my %versions;
   foreach my $item ( values %$items ) {
      next unless $self->valid_item($item);

      eval {
         my $func    = 'get_' . $item->{type};
         my $version = $self->$func(
            item      => $item,
            instances => $args{instances},
         );
         if ( $version ) {
            chomp $version unless ref($version);
            $versions{$item->{item}} = $version;
         }
      };
      if ( $EVAL_ERROR ) {
         PTDEBUG && _d('Error getting version for', Dumper($item), $EVAL_ERROR);
      }
   }

   return \%versions;
}

sub valid_item {
   my ($self, $item) = @_;
   return unless $item;

   if ( ($item->{type} || '') !~ m/$self->{valid_types}/ ) {
      PTDEBUG && _d('Invalid type:', $item->{type});
      return;
   }

   return 1;
}

sub get_os_version {
   my ($self) = @_;

   if ( $OSNAME eq 'MSWin32' ) {
      require Win32;
      return Win32::GetOSDisplayName();
   }

  chomp(my $platform = `uname -s`);
  PTDEBUG && _d('platform:', $platform);
  return $OSNAME unless $platform;

   chomp(my $lsb_release
            = `which lsb_release 2>/dev/null | awk '{print \$1}'` || '');
   PTDEBUG && _d('lsb_release:', $lsb_release);

   my $release = "";

   if ( $platform eq 'Linux' ) {
      if ( -f "/etc/fedora-release" ) {
         $release = `cat /etc/fedora-release`;
      }
      elsif ( -f "/etc/redhat-release" ) {
         $release = `cat /etc/redhat-release`;
      }
      elsif ( -f "/etc/system-release" ) {
         $release = `cat /etc/system-release`;
      }
      elsif ( $lsb_release ) {
         $release = `$lsb_release -ds`;
      }
      elsif ( -f "/etc/lsb-release" ) {
         $release = `grep DISTRIB_DESCRIPTION /etc/lsb-release`;
         $release =~ s/^\w+="([^"]+)".+/$1/;
      }
      elsif ( -f "/etc/debian_version" ) {
         chomp(my $rel = `cat /etc/debian_version`);
         $release = "Debian $rel";
         if ( -f "/etc/apt/sources.list" ) {
             chomp(my $code_name = `awk '/^deb/ {print \$3}' /etc/apt/sources.list | awk -F/ '{print \$1}'| awk 'BEGIN {FS="|"} {print \$1}' | sort | uniq -c | sort -rn | head -n1 | awk '{print \$2}'`);
             $release .= " ($code_name)" if $code_name;
         }
      }
      elsif ( -f "/etc/os-release" ) { # openSUSE
         chomp($release = `grep PRETTY_NAME /etc/os-release`);
         $release =~ s/^PRETTY_NAME="(.+)"$/$1/;
      }
      elsif ( `ls /etc/*release 2>/dev/null` ) {
         if ( `grep DISTRIB_DESCRIPTION /etc/*release 2>/dev/null` ) {
            $release = `grep DISTRIB_DESCRIPTION /etc/*release | head -n1`;
         }
         else {
            $release = `cat /etc/*release | head -n1`;
         }
      }
   }
   elsif ( $platform =~ m/(?:BSD|^Darwin)$/ ) {
      my $rel = `uname -r`;
      $release = "$platform $rel";
   }
   elsif ( $platform eq "SunOS" ) {
      my $rel = `head -n1 /etc/release` || `uname -r`;
      $release = "$platform $rel";
   }

   if ( !$release ) {
      PTDEBUG && _d('Failed to get the release, using platform');
      $release = $platform;
   }
   chomp($release);

   # For Gentoo, which returns a value in quotes
   $release =~ s/^"|"$//g;

   PTDEBUG && _d('OS version =', $release);
   return $release;
}

sub get_perl_version {
   my ($self, %args) = @_;
   my $item = $args{item};
   return unless $item;

   my $version = sprintf '%vd', $PERL_VERSION;
   PTDEBUG && _d('Perl version', $version);
   return $version;
}

sub get_perl_module_version {
   my ($self, %args) = @_;
   my $item = $args{item};
   return unless $item;
   
   # If there's a var, then its an explicit Perl variable name to get,
   # else the item name is an implicity Perl module name to which we
   # append ::VERSION to get the module's version.
   my $var          = $item->{item} . '::VERSION';
   my $version      = _get_scalar($var);
   PTDEBUG && _d('Perl version for', $var, '=', "$version");

   # Explicitly stringify this else $PERL_VERSION will return
   # as a version object.
   return $version ? "$version" : $version;
}

sub _get_scalar {
   no strict;
   return ${*{shift()}};
}

sub get_mysql_variable {
   my $self = shift;
   return $self->_get_from_mysql(
      show => 'VARIABLES',
      @_,
   );
}

sub _get_from_mysql {
   my ($self, %args) = @_;
   my $show      = $args{show};
   my $item      = $args{item};
   my $instances = $args{instances};
   return unless $show && $item;

   if ( !$instances || !@$instances ) {
      if ( $ENV{PTVCDEBUG} || PTDEBUG ) {
         _d('Cannot check', $item, 'because there are no MySQL instances');
      }
      return;
   }

   my @versions;
   my %version_for;
   foreach my $instance ( @$instances ) {
      my $dbh = $instance->{dbh};
      local $dbh->{FetchHashKeyName} = 'NAME_lc';
      my $sql = qq/SHOW $show/;
      PTDEBUG && _d($sql);
      my $rows = $dbh->selectall_hashref($sql, 'variable_name');

      my @versions;
      foreach my $var ( @{$item->{vars}} ) {
         $var = lc($var);
         my $version = $rows->{$var}->{value};
         PTDEBUG && _d('MySQL version for', $item->{item}, '=', $version,
            'on', $instance->{name});
         push @versions, $version;
      }

      $version_for{ $instance->{id} } = join(' ', @versions);
   }

   return \%version_for;
}

sub get_bin_version {
   my ($self, %args) = @_;
   my $item = $args{item};
   my $cmd  = $item->{item};
   return unless $cmd;

   my $sanitized_command = File::Basename::basename($cmd);
   PTDEBUG && _d('cmd:', $cmd, 'sanitized:', $sanitized_command);
   return if $sanitized_command !~ /\A[a-zA-Z0-9_-]+\z/;

   my $output = `$sanitized_command --version 2>&1`;
   PTDEBUG && _d('output:', $output);

   my ($version) = $output =~ /v?([0-9]+\.[0-9]+(?:\.[\w-]+)?)/;

   PTDEBUG && _d('Version for', $sanitized_command, '=', $version);
   return $version;
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
# End VersionCheck package
# ###########################################################################
