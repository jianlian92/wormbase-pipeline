#!/software/bin/perl -w
#
# script to find BLAT alignments that match to more than one CDS and
# set the Ignore tag in them so that they are not used in the
# transcript_builder script.
# 
# by Gary Williams
#
# Last updated by: $Author: pad $     
# Last updated on: $Date: 2013-08-14 12:19:59 $      

use strict;                                      
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Carp;
use Log_files;
use Storable;
use Modules::Overlap;

#use Ace;
#use Sequence_extract;
#use Coords_converter;
#use Feature_mapper;

######################################
# variables and command-line options # 
######################################

my ($help, $debug, $test, $verbose, $store, $wormbase, $database, $output, $species);


GetOptions ("help"       => \$help,
            "debug=s"    => \$debug,
	    "test"       => \$test,
	    "verbose"    => \$verbose,
	    "store:s"    => \$store,
	    "database:s" => \$database,
            "species:s"  => \$species,
	   );

if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
                             -organism => $species,
			   );
}

# Display help if required
&usage("Help") if ($help);

# in test mode?
if ($test) {
  print "In test mode\n" if ($verbose);
  
}

# establish log file.
my $log = Log_files->make_build_log($wormbase);

if (! defined $database) {$database = $wormbase->autoace}

$output = $wormbase->acefiles . "/ignore_bad_blat_alignments.ace";

#################################

# Set up top level base directories

my $chromosomes_dir = $wormbase->chromosomes; # AUTOACE CHROMSOMES
my $gff_dir         = $wormbase->gff;         # AUTOACE GFF
my $gff_splits_dir  = $wormbase->gff_splits;  # AUTOACE GFF SPLIT


my %mol_types = ( 'elegans'          => [qw( EST mRNA OST RST Trinity)],
                  'briggsae'         => [qw( mRNA EST Trinity)],
                  'remanei'          => [qw( mRNA EST Trinity)],
                  'brenneri'         => [qw( mRNA EST Trinity)],
                  'japonica'         => [qw( mRNA EST Trinity)],
                  'brugia'           => [qw( mRNA EST Trinity)],
                  'pristionchus'     => [qw( mRNA EST Trinity)],
                  'ovolvulus'        => [qw( mRNA EST Trinity)],
                  'sratti'           => [qw( mRNA EST)],
                );


##########################

$log->write_to("The following BLAT alignments span the introns of two or more CDS structures.\n\n");
$log->write_to("They should be inspected to see if the gene models should be merged or if the transcripts are chimeric or incompletely spliced operon transcripts\n\n");
$log->write_to("The following transcripts have had the Ignore tag set and will not be used for building Coding_transcripts in transcript_builder.pl\n\n");

$species = $wormbase->species;
open (ACE, ">$output") || die "Can't open $output\n";

my $regex = $wormbase->seq_name_regex;
my @chromosomes = $wormbase->get_chromosome_names(-mito => 0, -prefix => 1);

foreach my $chromosome (@chromosomes) {
  $log->write_to("\n\nChromosome: $chromosome\n");

  my $ovlp = Overlap->new($database, $wormbase);

  my @est_introns;
  my @rst_introns;
  my @ost_introns;
  my @mrn_introns;
  my @tri_introns;

  my $est_match;
  my $rst_match;
  my $ost_match;
  my $mrn_match;
  my $tri_match;

  if (grep /^EST$/, @{$mol_types{$species}}) {@est_introns = $ovlp->get_intron_from_exons($ovlp->get_EST_BEST($chromosome))};
  if (grep /^RST$/, @{$mol_types{$species}}) {@rst_introns = $ovlp->get_intron_from_exons($ovlp->get_RST_BEST($chromosome))};
  if (grep /^OST$/, @{$mol_types{$species}}) {@ost_introns = $ovlp->get_intron_from_exons($ovlp->get_OST_BEST($chromosome))};
  if (grep /^mRNA$/, @{$mol_types{$species}}) {@mrn_introns = $ovlp->get_intron_from_exons($ovlp->get_mRNA_BEST($chromosome))};
  if (grep /^Trinity$/, @{$mol_types{$species}}) {@tri_introns = $ovlp->get_intron_from_exons($ovlp->get_Trinity_BEST($chromosome))};
  
  my @CDS_introns = $ovlp->get_curated_CDS_introns($chromosome);

  if (grep /^EST$/, @{$mol_types{$species}}) {$est_match = $ovlp->compare(\@est_introns, exact_match => 1, same_sense => 0)};  # exact match to either sense
  if (grep /^RST$/, @{$mol_types{$species}}) {$rst_match = $ovlp->compare(\@rst_introns, exact_match => 1, same_sense => 0)};  # exact match to either sense
  if (grep /^OST$/, @{$mol_types{$species}}) {$ost_match = $ovlp->compare(\@ost_introns, exact_match => 1, same_sense => 0)};  # exact match to either sense
  if (grep /^mRNA$/, @{$mol_types{$species}}) {$mrn_match = $ovlp->compare(\@mrn_introns, exact_match => 1, same_sense => 0)};  # exact match to either sense
  if (grep /^Trinity$/, @{$mol_types{$species}}) {$tri_match = $ovlp->compare(\@tri_introns, exact_match => 1, same_sense => 0)};  # exact match to either sense


  my %overlapping_hsps = (); # EST/RST/OST/mRNA/Trinity transcripts that match a CDS, keyed by transcript name, value is array of matching CDSs

  foreach my $cds (@CDS_introns) {

    my ($cds_id) = ($cds->[0] =~ /($regex)/); # get just the sequence name
    

    if ((grep /^EST$/, @{$mol_types{$species}}) && $est_match->match($cds)) {
      my @ids = $est_match->matching_IDs;
      foreach my $id (@ids) {
	$overlapping_hsps{$id}{$cds_id} = 1;
      }
    } elsif ((grep /^RST$/, @{$mol_types{$species}}) && $rst_match->match($cds)) {
      my @ids = $rst_match->matching_IDs;
      foreach my $id (@ids) {
	$overlapping_hsps{$id}{$cds_id} = 1;
      }

    } elsif ((grep /^OST$/, @{$mol_types{$species}}) && $ost_match->match($cds)) {
      my @ids = $ost_match->matching_IDs;
      foreach my $id (@ids) {
	$overlapping_hsps{$id}{$cds_id} = 1;
      }

    } elsif ((grep /^mRNA$/, @{$mol_types{$species}}) && $mrn_match->match($cds)) {
      my @ids = $mrn_match->matching_IDs;
      foreach my $id (@ids) {
	$overlapping_hsps{$id}{$cds_id} = 1;
      }

    } elsif ((grep /^Trinity$/, @{$mol_types{$species}}) && $tri_match->match($cds)) {
      my @ids = $tri_match->matching_IDs;
      foreach my $id (@ids) {
	$overlapping_hsps{$id}{$cds_id} = 1;
      }

    }
  }
  
  # now look for transcripts that matched more than one CDS
  foreach my $trans (keys %overlapping_hsps) {
    my @cds = keys $overlapping_hsps{$trans};
    if (scalar @cds > 1) {
      $log->write_to("$trans matches @cds\n");
      print ACE "\n\n";
      print ACE "Sequence : $trans\n";
      print ACE "Ignore Remark \"matches more than one CDS: @cds\"\n";
      print ACE "Ignore Inferred_automatically \"ignore_bad_blat_alignments\"\n";
    }
  }
  
}
close (ACE);

$wormbase->load_to_database($database, $output, "ignore_bad_blat_alignments", $log);







$log->mail();
print "Finished.\n" if ($verbose);
exit(0);






##############################################################
#
# Subroutines
#
##############################################################

 

##########################################

sub usage {
  my $error = shift;

  if ($error eq "Help") {
    # Normal help menu
    system ('perldoc',$0);
    exit (0);
  }
}

##########################################




# Add perl documentation in POD format
# This should expand on your brief description above and 
# add details of any options that can be used with the program.  
# Such documentation can be viewed using the perldoc command.


__END__

=pod

=head2 NAME - script_template.pl

=head1 USAGE

=over 4

=item script_template.pl  [-options]

=back

This script does...blah blah blah

script_template.pl MANDATORY arguments:

=over 4

=item None at present.

=back

script_template.pl  OPTIONAL arguments:

=over 4

=item -h, Help

=back

=over 4
 
=item -debug, Debug mode, set this to the username who should receive the emailed log messages. The default is that everyone in the group receives them.
 
=back

=over 4

=item -test, Test mode, run the script, but don't change anything.

=back

=over 4
    
=item -verbose, output lots of chatty test messages

=back


=head1 REQUIREMENTS

=over 4

=item None at present.

=back

=head1 AUTHOR

=over 4

=item xxx (xxx@sanger.ac.uk)

=back

=cut
