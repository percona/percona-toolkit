# This program is copyright 2008-2011 Percona Inc.
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
# Sandbox package $Revision: 7140 $
# ###########################################################################

# Package: Sandbox
# Sandbox is an API for the test suite to access and control sandbox servers.
{
package Sandbox;

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

my $trunk = $ENV{PERCONA_TOOLKIT_BRANCH};

my %port_for = (
   master  => 12345,
   slave1  => 12346,
   slave2  => 12347,
   master1 => 12348, # master-master
   master2 => 12349, # master-master
);

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(basedir DSNParser) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   if ( !-d $args{basedir} ) {
      die "$args{basedir} is not a directory";
   }

   return bless { %args }, $class;
}

sub use {
   my ( $self, $server, $cmd ) = @_;
   _check_server($server);
   return if !defined $cmd || !$cmd;
   my $use = $self->_use_for($server) . " $cmd";
   MKDEBUG && _d('"Executing', $use, 'on', $server);
   eval {
      `$use`;
   };
   if ( $EVAL_ERROR ) {
      die "Failed to execute $cmd on $server: $EVAL_ERROR";
   }
   return;
}

sub create_dbs {
   my ( $self, $dbh, $dbs, %args ) = @_;
   die 'I need a dbh' if !$dbh;
   return if ( !ref $dbs || scalar @$dbs == 0 );
   my %default_args = (
      repl => 1,
      drop => 1,
   );
   %args = ( %default_args, %args );

   $dbh->do('SET SQL_LOG_BIN=0') unless $args{repl};

   foreach my $db ( @$dbs ) {
      $dbh->do("DROP DATABASE IF EXISTS `$db`") if $args{drop};

      my $sql = "CREATE DATABASE `$db`";
      eval {
         $dbh->do($sql);
      };
      die $EVAL_ERROR if $EVAL_ERROR;
   }

   $dbh->do('SET SQL_LOG_BIN=1');

   return;
}
   
sub get_dbh_for {
   my ( $self, $server, $cxn_ops ) = @_;
   _check_server($server);
   $cxn_ops ||= { AutoCommit => 1 };
   MKDEBUG && _d('dbh for', $server, 'on port', $port_for{$server});
   my $dp = $self->{DSNParser};
   my $dsn = $dp->parse('h=127.0.0.1,u=msandbox,p=msandbox,P=' . $port_for{$server});
   my $dbh;
   eval { $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), $cxn_ops) };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d('Failed to get dbh for', $server, ':', $EVAL_ERROR);
      return 0;
   }
   $dbh->{InactiveDestroy}  = 1; # Prevent destroying on fork.
   $dbh->{FetchHashKeyName} = 'NAME_lc' unless $cxn_ops && $cxn_ops->{no_lc};
   return $dbh;
}

sub load_file {
   my ( $self, $server, $file, $use_db ) = @_;
   _check_server($server);
   $file = "$trunk/$file";
   if ( !-f $file ) {
      die "$file is not a file";
   }

   my $d = $use_db ? "-D $use_db" : '';

   my $use = $self->_use_for($server) . " $d < $file";
   MKDEBUG && _d('Loading', $file, 'on', $server, ':', $use);
   eval { `$use` };
   if ( $EVAL_ERROR ) {
      die "Failed to execute $file on $server: $EVAL_ERROR";
   }

   return;
}

sub _use_for {
   my ( $self, $server ) = @_;
   return "$self->{basedir}/$port_for{$server}/use";
}

sub _check_server {
   my ( $server ) = @_;
   if ( !exists $port_for{$server} ) {
      die "Unknown server $server";
   }
   return;
}

sub wipe_clean {
   my ( $self, $dbh ) = @_;
   foreach my $db ( @{$dbh->selectcol_arrayref('SHOW DATABASES')} ) {
      next if $db eq 'mysql';
      next if $db eq 'information_schema';
      next if $db eq 'performance_schema';
      next if $db eq 'sakila';
      $dbh->do("DROP DATABASE IF EXISTS `$db`");
   }
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
}
# ###########################################################################
# End Sandbox package
# ###########################################################################
