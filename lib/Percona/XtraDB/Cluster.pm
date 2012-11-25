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
# Not really necessary, actually. But in case it's needed,
# wsrep_provider_version =~ /[0-9]+\.[0-9]+\(r([0-9]+)\)/ && $1 >= 137
sub find_cluster_nodes {
   my ($self, %args) = @_;

   my $dbh = $args{dbh};
   my $dsn = $args{dsn};
   my $dp  = $args{DSNParser};
   my $make_cxn = $args{make_cxn};

   # Ostensibly the caller should've done this already, but
   # useful for safety.
   # TODO this fails with a strange error.
   #$dp->fill_in_dsn($dbh, $dsn);
   
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
      my $node_dbh = eval { $dp->get_dbh(
            $dp->get_cxn_params($node_dsn), { AutoCommit => 1 }) };
      if ( $EVAL_ERROR ) {
         print STDERR "Cannot connect to ", $dp->as_string($node_dsn),
                      ", discovered through $sql: $EVAL_ERROR\n";
         # This is a bit strange, so an explanation is called for.
         # If there wasn't a port, that means that this bug
         # https://bugs.launchpad.net/percona-toolkit/+bug/1082406
         # isn't fixed on this version of PXC. We tried using the
         # master's port, but that didn't work. So try again, using
         # the default port.
         if ( !$port && $dsn->{P} != 3306 ) {
            $address .= ":3306";
            redo;
         }
         next;
      }
      PTDEBUG && _d('Connected to', $dp->as_string($node_dsn));
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
   my ($self, %args) = @_;
   my @cxns     = @{$args{cxns}};
   my $seen_ids = $args{seen_ids};
   PTDEBUG && _d("Removing duplicates from ", join " ", map { $_->name } @cxns);
   my @trimmed_cxns;

   for my $cxn ( @cxns ) {
      my $dbh  = $cxn->dbh();
      my $sql  = q{SELECT @@SERVER_ID};
      PTDEBUG && _d($sql);
      my ($id) = $dbh->selectrow_array($sql);
      PTDEBUG && _d('Server ID for ', $cxn->name, ': ', $id);

      if ( ! $seen_ids->{$id}++ ) {
         push @trimmed_cxns, $cxn
      }
      else {
         PTDEBUG && _d("Removing ", $cxn->name,
                       ", ID $id, because we've already seen it");
      }
   }

   return @trimmed_cxns;
}

sub same_cluster {
   my ($self, $cxn1, $cxn2) = @_;

   # They can't be the same cluster if one of them isn't in a cluster.
   return 0 if !$self->is_cluster_node($cxn1) || !$self->is_cluster_node($cxn2);

   my $cluster1 = $self->get_cluster_name($cxn1);
   my $cluster2 = $self->get_cluster_name($cxn2);

   return ($cluster1 || '') eq ($cluster2 || '');
}

sub autodetect_nodes {
   my ($self, %args) = @_;
   my $ms       = $args{MasterSlave};
   my $dp       = $args{DSNParser};
   my $make_cxn = $args{make_cxn};
   my $nodes    = $args{nodes};
   my $seen_ids = $args{seen_ids};

   return unless @$nodes;

   my @new_nodes;
   for my $node ( @$nodes ) {
      my @nodes = $self->find_cluster_nodes(
         dbh       => $node->dbh(),
         dsn       => $node->dsn(),
         make_cxn  => $make_cxn,
         DSNParser => $dp,
      );
      push @new_nodes, @nodes;
   }

   @new_nodes = $self->remove_duplicate_cxns(
      cxns     => \@new_nodes,
      seen_ids => $seen_ids
   );

   my @new_slaves;
   foreach my $node (@new_nodes) {
      my $node_slaves = $ms->get_slaves(
         dbh      => $node->dbh(),
         dsn      => $node->dsn(),
         make_cxn => $make_cxn,
      );
      push @new_slaves, @$node_slaves;
   }

   @new_slaves = $self->remove_duplicate_cxns(
      cxns     => \@new_slaves,
      seen_ids => $seen_ids
   );

   my @new_slave_nodes = grep { $self->is_cluster_node($_) } @new_slaves;

   return @new_nodes, @new_slaves,
          $self->autodetect_nodes(
            %args,
            nodes => \@new_slave_nodes,
          );
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
