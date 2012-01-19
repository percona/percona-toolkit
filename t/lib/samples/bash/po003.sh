#!/usr/bin/env bash

:

# ############################################################################
# Documentation
# ############################################################################
:<<'DOCUMENTATION'
=pod

=head1 NAME

pt-stalk - Wait for a condition to occur then begin collecting data.

=head1 OPTIONS

=over

=item --disk-pct-limit

type: int; default: 5

Exit if the disk is less than this %full.

=item --help

Print help.

=back

=head1 ENVIRONMENT

No env vars used.

=cut

DOCUMENTATION
