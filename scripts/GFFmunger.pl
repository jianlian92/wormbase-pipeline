#!/usr/local/bin/perl5.8.0 -w
#
# GFFmunger.pl
# 
# by Dan Lawson
#
# Last updated by: $Author: dl1 $
# Last updated on: $Date: 2004-12-22 12:43:38 $
#
# Usage GFFmunger.pl [-options]


#################################################################################
# variables                                                                     #
#################################################################################

use strict;
use lib -e "/wormsrv2/scripts"  ? "/wormsrv2/scripts"  : $ENV{'CVS_DIR'};
use Wormbase;
use IO::Handle;
use Getopt::Long;
use Ace;

##################################################
# Script variables and command-line options      #
##################################################
my $maintainers = "All";
my $WS_version = &get_wormbase_version_name;
our $lockdir = "/wormsrv2/autoace/logs/";


my $help;                      # Help/Usage page
my $all;                       # All of the following:
my $landmark;                  #   Landmark genes
my $UTR;                       #   UTRs 
my $WBGene;                    #   WBGene spans
my $CDS;                       #   CDS overload
my $debug;                     # debug
my $verbose;                   # verbose mode
our $log;

GetOptions (
	    "help"      => \$help,
	    "all"       => \$all,
	    "landmark"  => \$landmark,
	    "UTR"       => \$UTR,
	    "CDS"       => \$CDS,
	    "debug:s"   => \$debug
	    );

# help 
&usage("Help") if ($help);

# Use debug mode?
if($debug){
  print "DEBUG = \"$debug\"\n\n";
  ($maintainers = $debug . '\@sanger.ac.uk');
}

# get version number
our $WS_version = &get_wormbase_version;
 
&create_log_files;

##############################
# Paths etc                  #
##############################

my $datadir = "/wormsrv2/autoace/GFF_SPLITS/GFF_SPLITS";
my $gffdir  = "/wormsrv2/autoace/CHROMOSOMES";

# prepare array of file names and sort names
our @files = (
	      'CHROMOSOME_I',
	      'CHROMOSOME_II',
	      'CHROMOSOME_III',
	      'CHROMOSOME_IV',
	      'CHROMOSOME_V',
	      'CHROMOSOME_X',
	      );

our @gff_files = sort @files; 
undef @files; 

# check to see if full chromosome gff dump files exist
foreach my $file (@gff_files) {
    unless (-e "$gffdir/$file.gff") {
	&usage("No GFF file");
    }
    if (-e -z "$gffdir/$file.gff") {
	&usage("Zero length GFF file");
    }
}


my $addfile;
my $gffpath;


#################################################################################
# Main Loop                                                                     #
#################################################################################


if ($CDS || $all) {
    print LOG "# Overloading CDS lines\n";
    system ("overload_GFF_CDS_lines.pl $WS_version");                     # generate *.CSHL.gff files

    foreach my $file (@gff_files) {
	next if ($file eq "");              
	$gffpath = "$gffdir/${file}.gff";
	system ("mv -f $gffdir/$file.CSHL.gff $gffdir/$file.gff");        # copy *.CSHL.gff files back to *.gff name
    }

}

############################################################
# loop through each GFF file                               #
############################################################

foreach my $file (@gff_files) {

  next if ($file eq "");               # end loop if no filename
    
  $gffpath = "$gffdir/${file}.gff";

  print LOG "# File $file\n";
  
  if ($landmark || $all) {
    print LOG "# Adding ${file}.landmarks.gff file\n";
    $addfile = "$datadir/${file}.landmarks.gff";
    &addtoGFF($addfile,$gffpath);
  }

  if ($UTR || $all) {
    print LOG "# Adding ${file}.UTR.gff file\n";
    $addfile = "$datadir/${file}.UTR.gff";
    &addtoGFF($addfile,$gffpath);
  }
  
  print LOG "\n";
}



# Tidy up
close (LOG);


&mail_maintainer("GFFmunger.pl finished",$maintainers,$log);

exit(0);



###############################
# subroutines                 #
###############################


sub addtoGFF {
    
    my $addfile = shift;
    my $GFFfile = shift;
    
    system ("cat $addfile >> $GFFfile") && warn "ERROR: Failed to add $addfile to the main GFF file $GFFfile\n";

}


sub create_log_files{

  # Create history logfile for script activity analysis
  $0 =~ m/\/*([^\/]+)$/; system ("touch /wormsrv2/logs/history/$1.`date +%y%m%d`");

  # create main log file using script name for
  my $script_name = $1;
  $script_name =~ s/\.pl//; # don't really need to keep perl extension in log name
  my $rundate     = `date +%y%m%d`; chomp $rundate;
  $log        = "/wormsrv2/logs/$script_name.$rundate.$$";

  open (LOG, ">$log") or die "cant open $log";
  print LOG "$script_name\n";
  print LOG "started at ",`date`,"\n";
  print LOG "=============================================\n";
  print LOG "\n";

}

##########################################


##########################################
sub usage {
  my $error = shift;

  if ($error eq "Help") {
    # Normal help menu
    system ('perldoc',$0);
    exit (0);
  }
  elsif ($error eq "No GFF file") {
      # No GFF file to work from
      print "One (or more) GFF files are absent from $gffdir\n\n";
      exit(0);
  }
  elsif ($error eq "Zero length GFF file") {
      # Zero length GFF file
      print "One (or more) GFF files are zero length. The GFF dump may not have worked\n\n";
      exit(0);
  }
  elsif ($error eq "Debug") {
    # No debug person named
    print "You haven't supplied your name\nI won't run in debug mode until I know who you are\n\n";
    exit (0);
  }
}

################################################
#
# Post-processing GFF routines
#
################################################



__DATA__
clone_path
CDS
WBGene
pseudogenes
transposon
rna
worm_genes
Coding_transcript
coding_exon
exon
exon_tRNA
exon_pseudogene
exon_noncoding
intron
intron_all
Genefinder
history
repeats
assembly_tags
TSL_site
polyA
oligos
RNAi
TEC_RED
SAGE
allele
clone_ends
PCR_products
cDNA_for_RNAi
BLAT_EST_BEST
BLAT_EST_OTHER
BLAT_OST_BEST
BLAT_OST_OTHER
BLAT_TRANSCRIPT_BEST
BLAT_mRNA_BEST
BLAT_mRNA_OTHER
BLAT_EMBL_BEST
BLAT_EMBL_OTHER
BLAT_NEMATODE
BLAT_TC1_BEST
BLAT_TC1_OTHER
BLAT_ncRNA_BEST
BLAT_ncRNA_OTHER
Expr_profile
BLASTX
WABA_BRIGGSAE
operon
Oligo_set
rest
__END__



=pod

=head2 NAME - GFFsplitter.pl

=back 

=head1 USAGE

=over 4

=item GFFsplitter.pl <options>

=back

This script splits the large GFF files produced during the build process into
smaller files based on a named set of database classes to be split into.
Output written to /wormsrv2/autoace/GFF_SPLITS/WSxx

=over 4

=item MANDATORY arguments: 

None.

=back

=over 4

=item OPTIONAL arguments: -help, this help page.

= item -debug <user>, only email report/logs to <user>

= item -archive, archives (gzips) older versions of GFF_SPLITS directory

= item -verbose, turn on extra output to screen to help track progress


=back


=head1 AUTHOR - Daniel Lawson

Email dl1@sanger.ac.uk

=cut
