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
# Percona::XtraDB::Cluster package
# ###########################################################################
{
# Package: Percona::XtraDB::Cluster
# Helper methods for dealing with Percona XtraDB Cluster nodes.
package Percona::XtraDB::Cluster;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Lmo;
use Data::Dumper;

sub get_cluster_name {
   my ($self, $cxn) = @_;
   my $sql = "SHOW VARIABLES LIKE 'wsrep\_cluster\_name'";
   PTDEBUG && _d($cxn->name, $sql);
   my (undef, $cluster_name) = $cxn->dbh->selectrow_array($sql);
   return $cluster_name;
}

sub is_cluster_node {
   my ($self, $cxn) = @_;

   my $sql = "SHOW VARIABLES LIKE 'wsrep\_on'";
   PTDEBUG && _d($cxn->name, $sql);
   my $row = $cxn->dbh->selectrow_arrayref($sql);
   PTDEBUG && _d(Dumper($row));
   return unless $row && $row->[1] && ($row->[1] eq 'ON' || $row->[1] eq '1');

   my $cluster_name = $self->get_cluster_name($cxn);
   return $cluster_name;
}

sub same_node {
   my ($self, $cxn1, $cxn2) = @_;

   my $sub = sub {
      my $sql = shift;
      my @temp;
      PTDEBUG && _d($cxn1->name, $cxn2->name, $sql);
      for ($cxn1->dbh, $cxn2->dbh) {
         my (undef, $v) = $_->selectrow_array($sql);
         push @temp, $v;
      }
      return @temp
   };

   # We check several variables because, if these aren't the same,
   # we have our answer, but if they are, it doesn't necessarily
   # mean that we have the same node; See:
   # https://bugs.launchpad.net/percona-toolkit/+bug/1099845
   for my $val ('wsrep\_sst\_receive\_address', 'wsrep\_node\_name', 'wsrep\_node\_address') {
      my $sql = "SHOW VARIABLES LIKE '$val'";
      my ($val1, $val2) = $sub->($sql);
      return unless ($val1 || '') eq ($val2 || '');
   }

   return 1;

}

sub same_cluster {
   my ($self, $cxn1, $cxn2) = @_;

   # They can't be the same cluster if one of them isn't in a cluster.
   return 0 if !$self->is_cluster_node($cxn1) || !$self->is_cluster_node($cxn2);

   my $cluster1 = $self->get_cluster_name($cxn1);
   my $cluster2 = $self->get_cluster_name($cxn2);

   return ($cluster1 || '') eq ($cluster2 || '');
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
# End Percona::XtraDB::Cluster package
# ###########################################################################
