#!/usr/local/bin/perl5.8.0 -w
#
# get_pfam.pl
#
# by Darin Blasiar
#
# This script interogates an ACEDB database and returns all pfam/Interpro/blastx 
# data as appropriate and generates a suitable DB_remark
#
# Last updated on: $Date: 2004-06-11 14:35:23 $
# Last updated by: $Author: krb $


### DB_remark is generated as follows:  ###
#

###########################
# SEQUENCE OBJECTS        #
###########################
# Real Genes (clone.number)
# --------------------------
# 1. CGC name --> "C. elegans CGC name protein"
# 2. pfam motif --> "contains similarity to Pfam domain PFXXXXXX (title)"
#       * take ALL pfam motifs
# 3. interpro motif --> "contains similarity to Interpro domain XXXXXXX (title)"
#       * take ALL interpro motifs, if no Pfam hits
# 4. blastx similarity --> "contains similarity to SPECIES TITLE; ID"
#       * take highest scoring non-worm hit WITH a title, if no Interpro hits
#

#########################
# PSEUDOGENE OBJECTS    #
#########################
# -----------
#  w/ locus: "C. elegans TEXT pseudogene LOCUS"
#       * text is from Pseudogene(1)
#  w/o locus: NOTHING
#

#########################
# TRANSCRIPT OBJECTS    #
#########################

##   fields returned from database:
##       $transcript1 = $obj->Transcript(1); # type of transcript
##       $transcript2 = $obj->Transcript(2); # text
#
# tRNAs
#	w/locus { "C. elegans tRNA $locus"; }
#	w/o locus { "C. elegans predicted tRNA"; }
#   
# misc_RNA genes
#	w/ locus { "C. elegans non-protein coding RNA $locus"; }
#	w/o locus { "C. elegans probable non-coding RNA"; }
#    
# snRNA genes
#	w/locus) { "C. elegans small nuclear RNA $transcript2 $locus"; }
#	w/o locus { "C. elegans small nuclear RNA $transcript2"; }
#    
# snoRNA genes
#	w/locus { "C. elegans small nucleolar RNA $transcript2 $locus"; }
#	w/o locus { "C. elegans small nucleolar RNA $transcript2"; }
#   
# miRNA genes
#	w/locus { "C. elegans microRNA $locus"; }
#	w/o locus { "C. elegans predicted micro RNA"; }
#    
# stRNA genes
#	w/locus { "C. elegans regulatory RNA $locus"; }
#	w/o locus { "C. elegans predicted regulatory RNA"; }
#    
# scRNA genes
#	w/locus { "C. elegans small cytoplasmic RNA $locus"; }
#	w/o locus { "C. elegans predicted small cytoplasmic RNA"; }
    


use strict;
use Ace;
use lib -e "/wormsrv2/scripts" ? "/wormsrv2/scripts" : $ENV{CVS_DIR};
use Wormbase;
use Getopt::Long;
use Log_files;

#################################
#
#  Command line options stuff
#
#################################

my $test;     # for test mode, use test environment not on wormsrv2
my $debug;    # for debug mode, log file emailed to one person
my $database; # which database to query
my $output;   # choose different location of output file
my $maintainers = "All"; 

GetOptions("debug=s"    => \$debug,
	   "test"       => \$test,
	   "database=s" => \$database,
	   "output=s"   => \$output
	  );


# Use debug mode?
if($debug){
  print "DEBUG = \"$debug\"\n\n";
  ($maintainers = $debug . '\@sanger.ac.uk');
}


#################################
#
#  Misc. variables
#
#################################

my $tace = &tace; # to get tace version
my $log = Log_files->make_build_log() unless $test;
my $basedir;      # wormsrv2 or test environment
my $output_file;  # specify output file location
my $runtime;


# set up file paths

if($test) {
  $basedir = glob("~wormpub/TEST_BUILD");
}
else{
  $basedir = "/wormsrv2";
}

if($output){
  $output_file = $output;
}
else{
  $output_file   = "$basedir/wormbase/misc/misc_DB_remark.ace";
}
print "Output file is $output_file\n\n";
open (ACE,">$output_file") or die "cant open output file $output_file:\t$!\n";


# open database connection

my $db = Ace->connect (-path => "$database",
		       -program => $tace) || die "cannot connect to database at $database\n";


##################################################
#
# Main loop through elegans_CDS class
#
##################################################

$runtime= &runtime;
$log->write_to("$runtime: Processing CDS class\n");

# get CDSs for C. elegans
my @CDSs = $db->fetch(-query => 'Find elegans_CDS');

SUBSEQUENCE: foreach my $cds (@CDSs) {
  
  my (@motifs, @peptide_homols, $protein, $gene_name, $gene, $cgc_name, $cgc_protein_name);

  my $full_string = "";

  # grab Gene ID, and use this to look up Gene object to get CGC_name if present
  $gene_name = $cds->Gene;
  $gene = $db->fetch(Gene => $gene_name);
  if(defined($gene->CGC_name)){
    $cgc_name = $gene->CGC_name;
    $cgc_protein_name = uc($cgc_name);
  }
  
  # Find motifs
  $protein = $cds->Corresponding_protein;
  if ($protein) {
    @motifs = $protein->Motif_homol;

    # process motif information if present
    if($motifs[0]){
      $full_string .= "C. elegans $cgc_protein_name protein; " if ($cgc_name);
    }
    # get peptide homologies if no motif data
    else{
      @peptide_homols = $protein->Pep_homol;
      $full_string .= "C. elegans $cgc_protein_name protein" if ($cgc_name);
    }

    $protein->DESTROY();
  }


  # process motif information if present
  if($motifs[0]) {	
    my %pfamhits;
    my %interprohits;

    my %pfam_count;
    foreach my $motif (@motifs) {
      my $title = $motif->Title;
      if($motif =~ /PFAM/) {
	my ($pfam_motif) = $motif =~ /\w+\:(\w+)/;
	$pfamhits{$pfam_motif} = $title;
	my $pointer = $motif->right->right;
	$pfam_count{$motif->name} = 1;
	while($pointer->down ) {
	  $pfam_count{$motif->name}++;
	  $pointer = $pointer->down;
	}
      }
      if ($motif =~ /INTERPRO/) {
	my ($interpro_motif) = $motif =~ /\w+\:(\w+)/;
	$interprohits{$interpro_motif} = $title;
      }
      # free up memory
      $motif->DESTROY();      
    }

    my @pfamelements = %pfamhits;
    my @interproelements = %interprohits;

    if ($#pfamelements == 1) {
      foreach (keys %pfamhits) {
	$full_string .= "contains similarity to Pfam domain $_ ($pfamhits{$_})";
      }
      goto PRINTIT;
    }
    if ($#pfamelements > 1) {
      my $count = 1;
      $full_string .= "contains similarity to Pfam domains ";
      foreach (keys %pfamhits) {
	if($pfamhits{$_}){
	  $full_string .= "$_ ($pfamhits{$_})";
	  $full_string .=  "($pfam_count{\"PFAM:$_\"})" if $pfam_count{"PFAM:$_"} > 1;
	  if ($count < $#pfamelements) {
	    $full_string .= ", ";
	  }
	  $count += 2;
	}
      }
      goto PRINTIT;
    }

    if ($#interproelements == 1) {
      foreach (keys %interprohits) {
	$full_string .= "contains similarity to Interpro domain $_ ($interprohits{$_})";
      }
      goto PRINTIT;
    }
    if ($#interproelements > 1) {
      my $count = 1;
      $full_string .= "contains similarity to Interpro domains ";
      foreach (keys %interprohits) {
	$full_string .= "$_ ($interprohits{$_})";
	if ($count < $#interproelements) {
	  $full_string .= ", ";
	}
	$count += 2;
      }
      goto PRINTIT;
    }

  }

  #####################################################
  # no pfam or interpro hits; getting protein matches
  #####################################################

  elsif ($peptide_homols[0]) {

    # stored details of match with highest score
    my $max_score = 0;
    my $best_match = "";
    my $best_description = "";
    my $best_species = "";
  PROTEIN: foreach my $protein (@peptide_homols) {

    # ignore other worm matches
    next PROTEIN if (($protein =~ m/^BP\:CBP/) || ($protein =~ m/^WP\:CE/));

    my ($a,$b,$score,$d,$e,$f,$g) = $protein->row;

    my $title = $protein->Description;
    my $species = $protein->Species;
    
    # replace details if you find better score
    if (($score > $max_score) && $title && $species && $protein){
      $max_score = $score;
      $best_match = $protein;
      $best_description = $title;
      $best_species = $species;
    }

    $protein->DESTROY();
  }
    
    if ($cgc_name) {		# don't always take a peptide match, so can't add "; " above, must add here
      $full_string .= "; ";
    }
    $full_string .= "contains similarity to $best_species $best_description; $best_match";
    goto PRINTIT;

  }

 PRINTIT:

  next SUBSEQUENCE if ($full_string eq "");

  print ACE "CDS : $cds\n";
  print ACE "-D DB_remark\n";
  print ACE "DB_remark \"$full_string\"\n\n";

  # free up memory
  $cds->DESTROY();
}





###########################################
#
# process pseudogene class
#
###########################################

$runtime= &runtime;
$log->write_to("$runtime: Processing pseudogene class\n");


my @pseudogenes = $db->fetch(-query => 'Find elegans_pseudogenes');

PSEUDOGENE: foreach my $pseudogene (@pseudogenes) {

  my ($type, $gene_name, $gene, $cgc_name);

  my $full_string = "";

  # grab Gene ID, and use this to look up Gene object to get CGC_name if present
  $gene_name = $pseudogene->Gene;
  $gene = $db->fetch(Gene => $gene_name);
  if(defined($gene->CGC_name)){
    $cgc_name = $gene->CGC_name;
  }

  # get type of pseudogene
  $type = $pseudogene->Coding_pseudogene;

  if (($type) || ($cgc_name)) {
    if (($type) && ($cgc_name)) { 
      $full_string .= "C. elegans $type pseudogene $cgc_name"; 
    } 
    elsif ($type) { 
      $full_string .= "C. elegans $type pseudogene"; 
    } 
    elsif ($cgc_name) {
      $full_string .= "C. elegans pseudogene $cgc_name"; 
    }
  } 
  else {
    $full_string .= "C. elegans predicted pseudogene"; 
  }

  next PSEUDOGENE if ($full_string eq "");

  print ACE "Pseudogene : $pseudogene\n";
  print ACE "-D DB_remark\n";
  print ACE "DB_remark \"$full_string\"\n\n";

  # kill object to free memory
  $pseudogene->DESTROY();
}



###########################################
#
# process transcript class
#
###########################################

$runtime= &runtime;
$log->write_to("$runtime: Processing transcript class\n");


my @transcripts = $db->fetch(-query => 'Find elegans_RNA_genes');

TRANSCRIPT: foreach my $transcript (@transcripts) {

  my ($description, $cgc_name, $gene_name, $gene, $type, $method);

  my $full_string = "";

  # grab Gene ID, and use this to look up Gene object to get CGC_name if present
  $gene_name = $transcript->Gene;
  $gene = $db->fetch(Gene => $gene_name);
  if(defined($gene->CGC_name)){
    $cgc_name = $gene->CGC_name;
  }

  if($transcript->Method(1)){
    $method = $transcript->Method(1);
  }
  else{
    $log->write_to("ERROR: $transcript has no Method set\n");
    print "ERROR: $transcript has no Method set\n";
  }    

  # get type of transcript
  if($transcript->Transcript){
    $type = $transcript->Transcript; 
    ($description = $transcript->Transcript(2)) if ($transcript->Transcript(2)); # text field, not always present
  }
  else{
    $log->write_to("ERROR: $transcript has no Transcript tag\n");
    print "ERROR: $transcript has no Transcript tag\n";
  }

  # set empty text field if $description is empty to prevent -w warnings
  $description = "" if (!defined($description));

  if ($method eq 'tRNAscan-SE-1.23') { # tRNAs
    if ($cgc_name) {
      $full_string .= "C. elegans tRNA $cgc_name";
    } 
    else {
      $full_string .= "C. elegans predicted tRNA";
    }
  } 
  elsif ($type eq 'ncRNA') { # RNA genes
    if ($cgc_name) {
      $full_string .= "C. elegans non-protein coding RNA $cgc_name";
    } 
    else {
      $full_string .= "C. elegans probable non-coding RNA";
    }
  } 
  elsif ($type eq 'snRNA') { # snRNA genes
    if ($cgc_name) {
      $full_string .= "C. elegans small nuclear RNA $description $cgc_name";
    } 
    else {
      $full_string .= "C. elegans small nuclear RNA $description";
    }
  } 
  elsif ($type eq 'snoRNA') { # snoRNA genes
    if ($cgc_name) {
      $full_string .= "C. elegans small nucleolar RNA $description $cgc_name";
    } 
    else {
      $full_string .= "C. elegans small nucleolar RNA $description";
    }
  } 
  elsif ($type eq 'miRNA') { # miRNA genes
    if ($cgc_name) {
      $full_string .= "C. elegans microRNA $cgc_name";
    } 
    else {
      $full_string .= "C. elegans predicted micro RNA";
    }
  } 
  elsif ($type eq 'stRNA') { # stRNA genes
    if ($cgc_name) {
      $full_string .= "C. elegans regulatory RNA $cgc_name";
    } else {
      $full_string .= "C. elegans predicted regulatory RNA";
    }
  } 
  elsif ($type eq 'scRNA') { # scRNA genes
    if ($cgc_name) {
      $full_string .= "C. elegans small cytoplasmic RNA $cgc_name";
    } else {
      $full_string .= "C. elegans predicted small cytoplasmic RNA";
    }
  }

  next TRANSCRIPT if ($full_string eq "");

  print ACE "Transcript : $transcript\n";
  print ACE "-D DB_remark\n";
  print ACE "DB_remark \"$full_string\"\n\n";


}

# tidy up

close ACE;

$db->close;

# load the file to autoace
$runtime= &runtime;
$log->write_to("$runtime: loading results to $database\n");
&load_to_database($database,$output_file,"DB_remark");


$log->write_to("$runtime: Finished script\n\n");


$log->mail($maintainers) unless $test;



exit(0);






