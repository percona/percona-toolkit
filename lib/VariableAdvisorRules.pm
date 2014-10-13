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
# VariableAdvisorRules package
# ###########################################################################
{
# Package: VariableAdvisorRules
# VariableAdvisorRules specifies rules for checking MySQL variables.
package VariableAdvisorRules;
use base 'AdvisorRules';

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = $class->SUPER::new(%args);
   @{$self->{rules}} = $self->get_rules();
   PTDEBUG && _d(scalar @{$self->{rules}}, "rules");
   return $self;
}

# Each rules is a hashref with two keys:
#   * id       Unique PREFIX.NUMBER for the rule.
#   * code     Coderef to check rule, returns true if the rule matches.
sub get_rules {
   return
   {
      id   => 'auto_increment',
      code => sub {
         my ( %args ) = @_;
         my $vars = $args{variables};
         return unless defined $vars->{auto_increment_increment}
            && defined $vars->{auto_increment_offset};
         return    $vars->{auto_increment_increment} != 1
                || $vars->{auto_increment_offset}    != 1 ? 1 : 0;
      },
   },
   {
      id   => 'concurrent_insert',
      code => sub {
         my ( %args ) = @_;
         # MySQL 5.5 has named values.
         # http://dev.mysql.com/doc/refman/5.5/en/server-system-variables.html
         # https://bugs.launchpad.net/percona-toolkit/+bug/898138
         if (    $args{variables}->{concurrent_insert}
              && $args{variables}->{concurrent_insert} =~ m/[^\d]/ ) {
            return $args{variables}->{concurrent_insert} eq 'ALWAYS' ? 1 : 0;
         }
         return _var_gt($args{variables}->{concurrent_insert}, 1);
      },
   },
   {
      id   => 'connect_timeout',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{connect_timeout}, 10);
      },
   },
   {
      id   => 'debug',
      code => sub {
         my ( %args ) = @_;
         return $args{variables}->{debug} ? 1 : 0;
      },
   },
   {
      id   => 'delay_key_write',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{delay_key_write}, "ON");
      },
   },
   {
      id   => 'flush',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{flush}, "ON");
      },
   },
   {
      id   => 'flush_time',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{flush_time}, 0);
      },
   },
   {
      id   => 'have_bdb',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{have_bdb}, 'YES');
      },
   },
   {
      id   => 'init_connect',
      code => sub {
         my ( %args ) = @_;
         return $args{variables}->{init_connect} ? 1 : 0;
      },
   },
   {
      id   => 'init_file',
      code => sub {
         my ( %args ) = @_;
         return $args{variables}->{init_file} ? 1 : 0;
      },
   },
   {
      id   => 'init_slave',
      code => sub {
         my ( %args ) = @_;
         return $args{variables}->{init_slave} ? 1 : 0;
      },
   },
   {
      id   => 'innodb_additional_mem_pool_size',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{innodb_additional_mem_pool_size},
            20 * 1_048_576);  # 20M
      },
   },
   {
      id   => 'innodb_buffer_pool_size',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{innodb_buffer_pool_size},
            10 * 1_048_576);  # 10M
      },
   },
   {
      id   => 'innodb_checksums',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{innodb_checksums}, "ON");
      },
   },
   {
      id   => 'innodb_doublewrite',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{innodb_doublewrite}, "ON");
      },
   },
   {
      id   => 'innodb_fast_shutdown',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{innodb_fast_shutdown}, 1);
      },
   },
   {
      id   => 'innodb_flush_log_at_trx_commit-1',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{innodb_flush_log_at_trx_commit}, 1);
      },
   },
   {
      id   => 'innodb_flush_log_at_trx_commit-2',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{innodb_flush_log_at_trx_commit}, 0);
      },
   },
   {
      id   => 'innodb_force_recovery',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{innodb_force_recovery}, 0);
      },
   },
   {
      id   => 'innodb_lock_wait_timeout',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{innodb_lock_wait_timeout}, 50);
      },
   },
   {
      id   => 'innodb_log_buffer_size',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{innodb_log_buffer_size},
            16 * 1_048_576);  # 16M
      },
   },
   {
      id   => 'innodb_log_file_size',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{innodb_log_file_size},
            5 * 1_048_576);  # 5M
      },
   },
   {
      id   => 'innodb_max_dirty_pages_pct',
      code => sub {
         my ( %args ) = @_;
         my $mysql_version = $args{mysql_version};
         return 0 unless $mysql_version;
         return _var_lt($args{variables}->{innodb_max_dirty_pages_pct},
            ($mysql_version < '5.5' ? 90 : 75));
      },
   },
   {
      id   => 'key_buffer_size',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{key_buffer_size},
            8 * 1_048_576);  # 8M
      },
   },
   {
      id   => 'large_pages',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{large_pages}, "ON");
      },
   },
   {
      id   => 'locked_in_memory',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{locked_in_memory}, "ON");
      },
   },
   {
      id   => 'log_warnings-1',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{log_warnings}, 0);
      },
   },
   {
      id   => 'log_warnings-2',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{log_warnings}, 1);
      },
   },
   {
      id   => 'low_priority_updates',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{low_priority_updates}, "ON");
      },
   },
   {
      id   => 'max_binlog_size',
      code => sub {
         my ( %args ) = @_;
         return _var_lt($args{variables}->{max_binlog_size},
            1 * 1_073_741_824);  # 1G
      },
   },
   {
      id   => 'max_connect_errors',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{max_connect_errors}, 10);
      },
   },
   {
      id   => 'max_connections',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{max_connections}, 1_000);
      },
   },

   {
      id   => 'myisam_repair_threads',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{myisam_repair_threads}, 1);
      },
   },
   {
      id   => 'old_passwords',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{old_passwords}, "ON");
      },
   },
   {
      id   => 'optimizer_prune_level',
      code => sub {
         my ( %args ) = @_;
         return _var_lt($args{variables}->{optimizer_prune_level}, 1);
      },
   },
   {
      id   => 'port',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{port}, 3306);
      },
   },
   {
      id   => 'query_cache_size-1',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{query_cache_size},
            128 * 1_048_576);  # 128M
      },
   },
   {
      id   => 'query_cache_size-2',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{query_cache_size},
            512 * 1_048_576);  # 512M
      },
   },
   {
      id   => 'read_buffer_size-1',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{read_buffer_size}, 131_072);
      },
   },
   {
      id   => 'read_buffer_size-2',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{read_buffer_size},
            8 * 1_048_576);  # 8M
      },
   },
   {
      id   => 'read_rnd_buffer_size-1',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{read_rnd_buffer_size}, 262_144);
      },
   },
   {
      id   => 'read_rnd_buffer_size-2',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{read_rnd_buffer_size},
            4 * 1_048_576);  # 4M
      },
   },
   {
      id   => 'relay_log_space_limit',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{relay_log_space_limit}, 0);
      },
   },
   
   {
      id   => 'slave_net_timeout',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{slave_net_timeout}, 60);
      },
   },
   {
      id   => 'slave_skip_errors',
      code => sub {
         my ( %args ) = @_;
         return $args{variables}->{slave_skip_errors}
             && $args{variables}->{slave_skip_errors} ne 'OFF' ? 1 : 0;
      },
   },
   {
      id   => 'sort_buffer_size-1',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{sort_buffer_size}, 2_097_144);
      },
   },
   {
      id   => 'sort_buffer_size-2',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{sort_buffer_size},
            4 * 1_048_576);  # 4M
      },
   },
   {
      id   => 'sql_notes',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{sql_notes}, "OFF");
      },
   },
   {
      id   => 'sync_frm',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{sync_frm}, "ON");
      },
   },
   {
      id   => 'tx_isolation-1',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{tx_isolation}, "REPEATABLE-READ");
      },
   },
   {
      id   => 'tx_isolation-2',
      code => sub {
         my ( %args ) = @_;
         return
               _var_sneq($args{variables}->{tx_isolation}, "REPEATABLE-READ")
            && _var_sneq($args{variables}->{tx_isolation}, "READ-COMMITTED")
            ? 1 : 0;
      },
   },
   {
      id   => 'expire_logs_days',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{expire_logs_days}, 0)
            && _var_seq($args{variables}->{log_bin}, "ON");
      },
   },
   {
      id   => 'innodb_file_io_threads',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{innodb_file_io_threads}, 4)
            && $OSNAME ne 'MSWin32' ? 1 : 0;
      },
   },
   {
      id   => 'innodb_data_file_path',
      code => sub {
         my ( %args ) = @_;
         return
            ($args{variables}->{innodb_data_file_path} || '') =~ m/autoextend/
            ? 1 : 0;
      },
   },
   {
      id   => 'innodb_flush_method',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{innodb_flush_method}, 'O_DIRECT')
            && $OSNAME ne 'MSWin32' ? 1 : 0;
      },
   },
   {
      id   => 'innodb_locks_unsafe_for_binlog',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{innodb_locks_unsafe_for_binlog},
            "ON") && _var_seq($args{variables}->{log_bin}, "ON");
      },
   },
   {
      id   => 'innodb_support_xa',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{innodb_support_xa}, "ON")
            && _var_seq($args{variables}->{log_bin}, "ON");
      },
   },
   {
      id   => 'log_bin',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{log_bin}, "ON");
      },
   },
   {
      id   => 'log_output',
      code => sub {
         my ( %args ) = @_;
         return ($args{variables}->{log_output} || '') =~ m/TABLE/i ? 1 : 0;
      },
   },
   {
      id   => 'max_relay_log_size',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{max_relay_log_size}, 0)
            &&  _var_lt($args{variables}->{max_relay_log_size},
                  1 * 1_073_741_824)  ? 1 : 0;
      },
   },
   {
      id   => 'myisam_recover_options',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{myisam_recover_options}, "OFF")
            ||  _var_seq($args{variables}->{myisam_recover_options}, "DEFAULT")
               ? 1 : 0;
      },
   },
   {
      id   => 'storage_engine',
      code => sub {
         my ( %args ) = @_;
         return 0 unless $args{variables}->{storage_engine};
         return $args{variables}->{storage_engine} !~ m/InnoDB|MyISAM/i ? 1 : 0;
      },
   },
   {
      id   => 'sync_binlog',
      code => sub {
         my ( %args ) = @_;
         return
            _var_seq($args{variables}->{log_bin}, "ON")
            && (   _var_eq($args{variables}->{sync_binlog}, 0)
                || _var_gt($args{variables}->{sync_binlog}, 1)) ? 1 : 0;
      },
   },
   {
      id   => 'tmp_table_size',
      code => sub {
         my ( %args ) = @_;
         return ($args{variables}->{tmp_table_size} || 0)
              > ($args{variables}->{max_heap_table_size} || 0) ? 1 : 0;
      },
   },
   {
      id   => 'old mysql version',
      code => sub {
         my ( %args ) = @_;
         my $mysql_version = $args{mysql_version};
         return 0 unless $mysql_version;
         return 1 if   ($mysql_version == '3'   && $mysql_version < '3.23'  )
                    || ($mysql_version == '4'   && $mysql_version < '4.1.20')
                    || ($mysql_version == '5.0' && $mysql_version < '5.0.37')
                    || ($mysql_version == '5.1' && $mysql_version < '5.1.30');
         return 0;
      },
   },
   {
      id   => 'end-of-life mysql version',
      code => sub {
         my ( %args ) = @_;
         my $mysql_version = $args{mysql_version};
         return 0 unless $mysql_version;
         return $mysql_version < '5.1' ? 1 : 0;  # 5.1.x
      },
   },
};

sub _var_gt {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return $var > $val ? 1 : 0;
}

sub _var_lt {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return $var < $val ? 1 : 0;
}

sub _var_eq {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return $var == $val ? 1 : 0;
}

sub _var_neq {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return _var_eq($var, $val) ? 0 : 1;
}

sub _var_seq {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return $var eq $val ? 1 : 0;
}

sub _var_sneq {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return _var_seq($var, $val) ? 0 : 1;
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
# End VariableAdvisorRules package
# ###########################################################################
