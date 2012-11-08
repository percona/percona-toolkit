# This program is copyright 2011 Percona Inc.
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
# Percona::XtraDB::Cluster has helper methods to deal with Percona XtraDB Cluster
# based servers

package Percona::XtraDB::Cluster;
use Mo;
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub is_cluster_node {
   my ($self, $cxn) = @_;
   return $self->{is_cluster_node}->{$cxn} if defined $self->{is_cluster_node}->{$cxn};

   my $sql = "SHOW VARIABLES LIKE 'wsrep_on'";
   PTDEBUG && _d($sql);
   my $row = $cxn->dbh->selectrow_arrayref($sql);
   PTDEBUG && _d(defined $row ? @$row : 'undef');
   $self->{is_cluster_node}->{$cxn} = $row && $row->[1]
                            ? ($row->[1] eq 'ON' || $row->[1] eq '1')
                            : 0;

   return $self->{is_cluster_node}->{$cxn};
}

sub same_cluster {
   my ($self, $cxn1, $cxn2) = @_;
   return unless $self->is_cluster_node($cxn1) && $self->is_cluster_node($cxn2);
   return if $self->is_master_of($cxn1, $cxn2) || $self->is_master_of($cxn2, $cxn1);

   my $sql = q{SHOW VARIABLES LIKE 'wsrep_cluster_name'};
   PTDEBUG && _d($sql);
   my (undef, $row)      = $cxn1->dbh->selectrow_array($sql);
   my (undef, $cxn2_row) = $cxn2->dbh->selectrow_array($sql);

   return unless $row eq $cxn2_row;

   # Now it becomes tricky. Ostensibly clusters shouldn't have the
   # same name, but tell that to the world.
   $sql = q{SHOW VARIABLES LIKE 'wsrep_cluster_address'};
   PTDEBUG && _d($sql);
   my (undef, $addr)      = $cxn1->dbh->selectrow_array($sql);
   my (undef, $cxn2_addr) = $cxn2->dbh->selectrow_array($sql);

   # If they both have gcomm://, then they are both the first
   # node of a cluster, so they can't be in the same one.
   return if $addr eq 'gcomm://' && $cxn2_addr eq 'gcomm://';

   if ( $addr eq 'gcomm://' ) {
      $addr      = $self->_find_full_gcomm_addr($cxn1->dbh);
   }
   elsif ( $cxn2_addr eq 'gcomm://' ) {
      $cxn2_addr  = $self->_find_full_gcomm_addr($cxn2->dbh);
   }

   # Meanwhile, if they have the same address, then
   # they are definitely part of the same cluster
   return 1 if lc($addr) eq lc($cxn2_addr);

   # However, this still leaves us with the issue that
   # the cluster addresses could look like this:
   # node1 -> node2, node2 -> node1,
   # or
   # node1 -> node2 addr,
   # node2 -> node3 addr,
   # node3 -> node1 addr,
   # TODO No clue what to do here
   return 1;
}

sub is_master_of {
   my ($self, $cxn1, $cxn2) = @_;

   my $cxn2_dbh = $cxn2->dbh;
   my $sql      = q{SHOW SLAVE STATUS};
   PTDEBUG && _d($sql);
   local $cxn2_dbh->{FetchHashKeyName} = 'NAME_lc';
   my $slave_status = $cxn2_dbh->selectrow_hashref($sql);
   return unless ref($slave_status) eq 'HASH';

   my $port = $cxn1->dsn->{P};
   return unless $slave_status->{master_port} eq $port;
   return 1 if $cxn1->dsn->{h} eq $slave_status->{master_host};

   # They might be the same but in different format
   my $host        = scalar gethostbyname($cxn1->dsn->{h});
   my $master_host = scalar gethostbyname($slave_status->{master_host});
   return 1 if $master_host eq $host;
   return;
}

sub _find_full_gcomm_addr {
   my ($self, $dbh) = @_;

   my $sql = q{SHOW VARIABLES LIKE 'wsrep_provider_options'};
   PTDEBUG && _d($sql);
   my (undef, $provider_opts) = $dbh->selectrow_array($sql);
   my ($prov_addr)  = $provider_opts =~ m{\Qgmcast.listen_addr\E\s*=\s*tcp://([^:]+:[0-9]+)\s*;}i;
   my $full_gcomm = "gcomm://$prov_addr";
   PTDEBUG && _d("gcomm address: ", $full_gcomm);
   return $full_gcomm;
}

1;
}
