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

use Mo;
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

   my $sql = "SHOW VARIABLES LIKE 'wsrep\_sst\_receive\_address'";
   PTDEBUG && _d($cxn1->name, $sql);
   my (undef, $val1) = $cxn1->dbh->selectrow_array($sql);
   PTDEBUG && _d($cxn2->name, $sql);
   my (undef, $val2) = $cxn2->dbh->selectrow_array($sql);

   return ($val1 || '') eq ($val2 || '');
}

# TODO: Check that the PXC version supports wsrep_incoming_addresses
sub find_cluster_nodes {
   my ($self, %args) = @_;

   my $dbh = $args{dbh};
   my $dsn = $args{dsn};
   my $dp  = $args{DSNParser};
   my $make_cxn = $args{make_cxn};


   my $sql = q{SHOW STATUS LIKE 'wsrep_incoming_addresses'};
   PTDEBUG && _d($sql);
   my (undef, $addresses) = $dbh->selectrow_array($sql);
   PTDEBUG && _d("Cluster nodes found: ", $addresses);
   return unless $addresses;

   my @addresses = grep !/\Aunspecified\z/i,
                   split /,\s*/, $addresses;

   my @nodes;
   foreach my $address ( @addresses ) {
      my ($host, $port) = split /:/, $address;
      my $spec = "h=$host"
               . ($port ? ",P=$port" : "");
      my $node_dsn = $dp->parse($spec, $dsn);
      my $node_dbh = eval {
         $dp->get_dbh(
            $dp->get_cxn_params($node_dsn), { AutoCommit => 1 });
         PTDEBUG && _d('Connected to', $dp->as_string($node_dsn));
      };
      if ( $EVAL_ERROR ) {
         print STDERR "Cannot connect to ", $dp->as_string($node_dsn),
                      ", discovered through $sql: $EVAL_ERROR\n";
         next;
      }
      $node_dbh->disconnect();

      push @nodes, $make_cxn->(dsn => $node_dsn);
   }

   return @nodes;
}

# There's two reasons why there might be dupes:
# If the "master" is a cluster node, then a DSN table might have been
# used, and it may have all nodes' DSNs so the user can run the tool
# on any node, in which case it has the "master" node, the DSN given
# on the command line.
# On the other hand, maybe find_cluster_nodes worked, in which case
# we definitely have a dupe for the master cxn, but we may also have a
# dupe for every other node if this was unsed in conjunction with a
# DSN table.
# So try to detect and remove those.

sub remove_duplicate_cxns {
   my ($self, @cxns) = @_;
   my %addresses;

   my @unique_cxns;
   CXN:
   foreach my $cxn ( @cxns ) {
      # If not a cluster node, assume that it's unique
      if ( !$self->cluster_node($cxn) ) {
         push @unique_cxns, $cxn;
         next CXN;
      }

      # Otherwise, check that it only shows up once.
      my $dbh = $cxn->dbh();
      my $sql = q{SHOW VARIABLES LIKE 'wsrep_sst_receive_address'};
      PTDEBUG && _d($dbh, $sql);
      my (undef, $receive_addr) = $dbh->selectrow_array();

      if ( !$receive_addr ) {
         PTDEBUG && _d(q{Query returned nothing, assuming that it's },
                       q{not a duplicate});
         push @unique_cxns, $cxn;
      }
      elsif ( $addresses{$receive_addr}++ ) {
         PTDEBUG && _d('Removing ', $cxn->name, 'from slaves',
            'because we already have a node from this address');
      }
      else {
         push @unique_cxns, $cxn;
      }

   }
   warn "<@cxns>";
   warn "<@unique_cxns>";
   return @unique_cxns;
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
