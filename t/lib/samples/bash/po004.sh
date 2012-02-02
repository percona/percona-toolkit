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

=item --disk-bytes-free

type: size; default: 100M

Fall apart if there's less than this many bytes free on the disk.

=item --help

Print help.

=back

=head1 ENVIRONMENT

No env vars used.

=cut

DOCUMENTATION
