# This program is copyright 2012 Percona Inc.
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

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ($class, %args) = @_;
   return bless {}, $class;
}

sub parse_server_response {
   my ($self, %args) = @_;
   my @required_args = qw(response);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($response) = @args{@required_args};

   PTDEBUG && _d('Server response:', $response); 

   my %items = map {
      my ($item, $type, $vars) = split(";", $_);
      my (@vars)               = split(",", ($vars || ''));
      $item => {
         item => $item,
         type => $type,
         vars => \@vars,
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
   my $dbh     = $args{dbh}; # optional

   my %versions;
   foreach my $item ( values %$items ) {
      next unless $self->valid_item($item);

      eval {
         my $func    = 'get_' . $item->{type};
         my $version = $self->$func(
            item => $item,
            dbh  => $dbh,
         );
         if ( $version ) {
            chomp $version;
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
   return 1;
}

sub get_os {
   my ($self) = @_;

  chomp(my $platform = `uname -s`);
  PTDEBUG && _d('platform:', $platform);
  return unless $platform;

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
      elsif ( `ls /etc/*release 2>/dev/null` ) {
         if ( `grep DISTRIB_DESCRIPTION /etc/*release 2>/dev/null` ) {
            $release = `grep DISTRIB_DESCRIPTION /etc/*release | head -n1`;
         }
         else {
            $release = `cat /etc/*release | head -n1`;
         }
      }
   }
   elsif ( $platform =~ m/^(BSD|Darwin)$/ ) {
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

   PTDEBUG && _d('OS version =', $release);
   return $release;
}

sub get_perl_variable {
   my ($self, %args) = @_;
   my $item = $args{item};
   return unless $item;

   # Can't just stringify $PERL_VERSION because on 5.8 it doesn't work.
   # So %vd coerces the version into a string on 5.8+.
   if ( $item->{item} eq 'Perl' ) {
      my $version = sprintf '%vd', $PERL_VERSION;
      PTDEBUG && _d('Perl version', $version);
      return $version;
   }

   # If there's a var, then its an explicit Perl variable name to get,
   # else the item name is an implicity Perl module name to which we
   # append ::VERSION to get the module's version.   
   my $var     = $item->{vars}->[0] || ($item->{item} . '::VERSION');
   my $version = do { no strict; ${*{$var}}; }; 
   PTDEBUG && _d('Perl version for', $var, '=', "$version");

   # Explicitly stringify this else $PERL_VERSION will return
   # as a version object.
   return $version ? "$version" : $version;
}

sub get_mysql_variable {
   my $self = shift;
   return $self->_get_from_mysql(
      show => 'VARIABLES',
      @_,
   );
}

# This isn't implemented yet.  It's easy to do (TYPE=mysql_status),
# but it may be overkill.
#sub get_mysql_status {
#   my $self = shift;
#   return $self->_get_from_mysql(
#      show => 'STATUS',
#      @_,
#   );
#}

sub _get_from_mysql {
   my ($self, %args) = @_;
   my $show = $args{show};
   my $item = $args{item};
   my $dbh  = $args{dbh};
   return unless $show && $item && $dbh;

   local $dbh->{FetchHashKeyName} = 'NAME_lc';
   my $sql = qq/SHOW $show/;
   PTDEBUG && _d($sql);
   my $rows = $dbh->selectall_hashref($sql, 'variable_name');

   my @versions;
   foreach my $var ( @{$item->{vars}} ) {
      $var = lc($var);
      my $version = $rows->{$var}->{value};
      PTDEBUG && _d('MySQL version for', $item->{item}, '=', $version);
      push @versions, $version;
   }

   return join(' ', @versions);
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
