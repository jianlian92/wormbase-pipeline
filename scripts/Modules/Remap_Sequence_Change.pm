#!/usr/bin/env perl
#===============================================================================
#
#         FILE: Remap_Sequence_Change.pm
#
#  DESCRIPTION: Functions for remapping locations based on changes in
#               chromosome sequences between database releases.
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES: 
#      $Author: gw3 $
#      COMPANY:
#     $Version:  $
#      CREATED: 2006-02-27
#        $Date: 2006-02-27 16:34:16 $
#===============================================================================
package Remap_Sequence_Change;

use strict;
use warnings;

##########################################################
# 
# Name:      read_mapping_data
# Usage:     @mapping_data = &read_mapping_data($release1, $release2);
# Function:  reads the data used to remap across release
# Args:      $release1, $release2, the first and last wormbase release
#                  numbers to use e.g. 140, 150 to convert data made using wormbase
#                  release WS140 to the coordinates of release WS150
# Returns:   the mapping data, for use in remap_gff()
#

# the mismatch_start value is the start of the mismatch, it is the first position which doesn't match
# the mismatch_end value is the base past the end of the mismatch region, the first base which matches again
# ($mismatch_start1, $mismatch_end1, $len1, $mismatch_start2, $mismatch_end2, $len2, $flipped)
                                                                                                                                                            
#
# Input files look like:
# Chromosome: I
# 4765780 4765794 14      4765780 4765794 14      0
                                                                                                                                                            
                                                                                                                                                            
sub read_mapping_data {

  my ($release1, $release2) = @_;
                                                                                                                                           
  # array (one for each release) of hashes (keyed by chromosome number) of list (one for each difference) of list (one for each field)
  # access like: $fields_hashref = @{ $mapping_data[$release]{$chrom}[$next_difference] }
  my @mapping_data;
                                                                                                                                                            
  foreach my $release (($release1+1) .. $release2) {
    my %chroms;
    my $infile = "/nfs/disk100/wormpub/CHROMOSOME_DIFFERENCES/sequence_differences.WS$release";
    open (IN, "< $infile") || die "Can't open $infile\n";
    my $chrom;
    while (my $line = <IN>) {
      chomp $line;
      if ($line =~ /Chromosome:\s+(\S+)/) {
        $chrom = $1;
      } else {
        my @fields = split /\t/, $line;
        #print "fields=@fields\n";
                                                                                                                                                            
        push @{ $mapping_data[$release]{$chrom} }, [@fields];
                                                                                                                                                            
        # debug
        #my $a = $mapping_data[$release]{$chrom} ;
        #foreach my $b (@$a) {
        #  print "just pushed array @$b\n";
        #}
      }
    }
    close(IN);
  }
                                                                                                                                                            
  return @mapping_data;
}


##########################################################
# 
# Name:      remap_ace
# Usage:     ($new_start, $new_end) = remap_ace($chromosome, $start, $end, $release1, $release2, @mapping_data);
# Function:  does the remapping of a pair of location values for an ACE file
# Args:      $chromosome, the chromosome number, e.g. 'III'
#            $start, the start value of the location coordinate
#            $end, the end value of the location coordinate ($end < $start for reverse sense)
#            $release1, $release2, the first and last wormbase release
#                  numbers to use e.g. 140, 150 to convert data made using wormbase
#                  release WS140 to the coordinates of release WS150
#            @mapping_data - data as returned by read_mapping_data
# Returns:   $new_start, $new_end, $new_sense - the updated location coordinates
#

sub remap_ace {
  my ($chromosome, $start, $end, $release1, $release2, @mapping_data) = @_;
                      
  my $sense = "+";

  if ($start > $end) {
    $sense = "-";
    my $tmp = $start;
    $start = $end;
    $end = $tmp;
  }

  ($start, $end, $sense) = remap_gff($chromosome, $start, $end, $sense, $release1, $release2, @mapping_data);

  if ($sense eq '-') {
    my $tmp = $start;
    $start = $end;
    $end = $tmp;
  }
                                                   
  return ($start, $end);

}

##########################################################
# 
# Name:      remap_gff
# Usage:     ($new_start, $new_end, $new_sense) = remap_gff($chromosome, $start, $end, $sense, $release1, $release2, @mapping_data);
# Function:  does the remapping of a pair of location values for a GFF file
# Args:      $chromosome, the chromosome number, e.g. 'III'
#            $start, the start value of the location coordinate
#            $end, the end value of the location coordinate (always >= $start)
#            $sense, the sense "+" or "-" of the coordinate
#            $release1, $release2, the first and last wormbase release
#                  numbers to use e.g. 140, 150 to convert data made using wormbase
#                  release WS140 to the coordinates of release WS150
#            @mapping_data - data as returned by read_mapping_data
# Returns:   $new_start, $new_end, $new_sense - the updated location coordinates
#

sub remap_gff {
  my ($chromosome, $start, $end, $sense, $release1, $release2, @mapping_data) = @_;
                                                                                                                                                            
  if ($chromosome =~ /CHROMOSOME_(\S+)/) {$chromosome = $1;}
                                                                                                                                                            
  foreach my $release (($release1+1) .. $release2) {
                                                                                                                                                            
    if (exists $mapping_data[$release]{$chromosome}) {
      foreach  my $fields (@{$mapping_data[$release]{$chromosome}}) {
        #print "$release $chromosome fields= @$fields \n";

# The mismatch_start value is the start of the mismatch, it is the first position which doesn't match.
# The mismatch_end value is the base past the end of the mismatch region, the first base which matches again
# ($mismatch_start1, $mismatch_end1, $len1, $mismatch_start2, $mismatch_end2, $len2, $flipped)
        my ($mismatch_start1, $mismatch_end1, $len1, $mismatch_start2, $mismatch_end2, $len2, $flipped) = @$fields;

# N.B. mismatch values are in the normal perl coordinate system starting at position 0.
# Convert them to the GFF coordinates system starting at position 1.
	$mismatch_start1++;
	$mismatch_end1++;
                                                                                                                                                            
        if ($flipped) {    # is the feature inside a flipped region?
                                                                                                                                                            
          if ($start >= $mismatch_start1 && $end < $mismatch_end1) {
                                                                                                                                                            
            if ($sense eq '+') {$sense = '-';} else {$sense = '+';} # flip the sense
            $start = $mismatch_start1 + $mismatch_end1 - $start; # flip the start and end positions
            $end = $mismatch_start1 + $mismatch_end1 - $end;
            if ($start > $end) {
              my $tmp = $start;
              $start = $end;
              $end = $tmp;
            }
          }
                                                                                                                                                            
        } else {
          # if the start or end are beyond the start of the change region, apply any shift
                                                                                                                                                            
          if ($start >= $mismatch_end1) { # if past the end of the change region, shift it
            $start += $len2 - $len1;
          } elsif ($start >= $mismatch_start1 && $start - $mismatch_start1 > $len2 ) { # if was in the change region and now out, set it to the end
            $start = $mismatch_start1 + $len2;
          }
                                                                                                                                                            
          if ($end >= $mismatch_end1) { # if past the end of the change region, shift it
            $end += $len2 - $len1;
          } elsif ($end >= $mismatch_start1 && $end - $mismatch_start1 > $len2) { # if was in the change region and now out, set it to the end
            $end = $mismatch_start1 + $len2;
          }
                                                                                                                                                            
                                                                                                                                                            
        }
                                                                                                                                                            
      }
    } else {
      #print "no change: doesn't exist: $release $chromosome\n";
    }
  }
                                                                                                                                                            
                                                                                                                                                            
  return ($start, $end, $sense);
}






1;

__END__

=pod

=head2 NAME - Remap_Sequence_Change.pm

=head2 USAGE

 use Remap_Sequence_Change;
 Remap_Sequence_Change::Function()

=over 4

=head2 DESCRIPTION 

Module for remapping chromosomal sequence locations across releases.

=back

=head3 FUNCTIONS

=over 4

=item @mapping_data = &read_mapping_data($release1, $release2);

Reads in the mapping information from the files craeted during the
build of each release.

=back

=over 4

=item ($new_start, $new_end) = remap_ace($chromosome, $start, $end, @mapping_data);

Maps a start and end location pair of ACE file chromosomal
coordinates, to the new coordinates.

=back

=item ($new_start, $new_end, $new_sense) = remap_ace($chromosome, $start, $end, $sense, @mapping_data);

Maps a start and end location pair of GFF file chromosomal
coordinates, with their sense ("+" or "-") to the new coordinates.

=back

=head3 AUTHOR
$Author: gw3 $

=cut
