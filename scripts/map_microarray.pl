#!/usr/local/bin/perl5.8.0 -w
#
# map_microarray.pl
#
# Add information to Microarray_results objects based on overlaps in GFF files 
#
# by Anon
#
# Last updated by: $Author: krb $                      
# Last updated on: $Date: 2004-10-19 14:58:12 $        


use strict;
use lib -e "/wormsrv2/scripts" ? "/wormsrv2/scripts" : $ENV{'CVS_DIR'};
use Wormbase;
use IO::Handle;
use Getopt::Long;
use Cwd;
use Ace;


######################################
# variables and command-line options #
######################################

my $tace        = &tace;                                  # tace executable path
my $dbdir       = "/wormsrv2/autoace";                    # Database path

my $maintainers = "All";
my $rundate = &rundate;
my $runtime = &runtime;
my $help;       # Help perdoc
my $test;       # Test mode
my $debug;      # Debug mode, verbose output to user running script
my $log = Log_files->make_build_log();
my $verbose;    # verbose mode, extra output to screen

my $outfile = "/wormsrv2/autoace/acefiles/microarray_mappings.ace";

GetOptions ("debug=s"   => \$debug,
	    "test"      => \$test,
            "help"      => \$help);


# Display help if required
&usage("Help") if ($help);

# Use debug mode?
if($debug){
  print "DEBUG = \"$debug\"\n\n";
  ($maintainers = $debug . '\@sanger.ac.uk');
}

# connect to database
print  "Opening database ..\n" if ($debug);
my $db = Ace->connect(-path=>$dbdir,
                      -program =>$tace) || do { print "Connection failure: ",Ace->error; die();};


if ($debug) {
    my $count = $db->fetch(-query=> 'find PCR_product where Microarray_results');
    print "checking $count PCR_products\n\n";

    $count = $db->fetch(-query=> 'find Oligo_set where Microarray_results');
    print "checking $count Oligo_sets\n\n";

}

my $microarray_results;
my @CDSs;
my @Pseudo;
my $cds;
my $gene;
my $pseudo;
my $locus;

open (OUTPUT, ">$outfile") or die "Can't open the output file $outfile\n";

###########################################
# PCR_products and SMD_microarray results #
###########################################

my $i = $db->fetch_many(-query=> 'find PCR_product where Microarray_results');  
while (my $obj = $i->next) {
    
  print "$obj\t" if ($debug);

  # Microarray_results
  
  $microarray_results = $obj->Microarray_results;
  
  @CDSs    = $obj->Overlaps_CDS;
  @Pseudo  = $obj->Overlaps_pseudogene;
  
  print "Microarray_results : \"$microarray_results\"\tCDS: " . (scalar @CDSs) . " Pseudo: " . (scalar @Pseudo) . "\n" if ($debug);
  
  if (scalar @CDSs > 0) {
    print OUTPUT "\nMicroarray_results : \"$microarray_results\"\n";
    foreach $cds (@CDSs) {
      print OUTPUT "CDS \"$cds\"\n";
      $gene   = $obj->Overlaps_CDS->Gene;
    }
    
    print OUTPUT "Gene $gene\n" if (defined $gene);
    print OUTPUT "\n";
  }
  
  if (scalar @Pseudo > 1) {
    print OUTPUT "\n// Microarray_results : \"$microarray_results\"\n";
    foreach $pseudo (@Pseudo) {
      print OUTPUT "// Predicted_pseudogene \"$pseudo\"\n";
    }
    print OUTPUT "\n";
  }
  
  @CDSs    = "";
  @Pseudo = "";
  $gene = "";
  $obj->DESTROY();
}

###########################################
# Oligo_sets and Aff_microarray results #
###########################################

$i = $db->fetch_many(-query=> 'find Oligo_set where Microarray_results');  
while (my $obj = $i->next) {
  
  print "$obj\t" if ($debug);

  # Microarray_results
    
  $microarray_results = $obj->Microarray_results;
  
  @CDSs    = $obj->Overlaps_CDS;
  @Pseudo  = $obj->Overlaps_pseudogene;
    
  print "Microarray_results : \"$microarray_results\"\tCDS: " . (scalar @CDSs) . " Pseudo: " . (scalar @Pseudo) . "\n" if ($debug);
    
  if (scalar @CDSs > 0) {
    print OUTPUT "\nMicroarray_results : \"$microarray_results\"\n";
    foreach $cds (@CDSs) {
      print OUTPUT "CDS \"$cds\"\n";
      $gene   = $obj->Overlaps_CDS->Gene;
    }
    
    print OUTPUT "Gene $gene\n" if (defined $gene);
    print OUTPUT "\n";
  }
  
  if (scalar @Pseudo > 1) {
    print OUTPUT "\n// Microarray_results : \"$microarray_results\"\n";
    foreach $pseudo (@Pseudo) {
      print OUTPUT "// Predicted_pseudogene \"$pseudo\"\n";
    }
    print OUTPUT "\n";
  }
  
  @CDSs    = "";
  @Pseudo = "";
  $gene = "";
  $obj->DESTROY();
}


close OUTPUT;
$db->close;

$log->mail("$maintainers","BUILD REPORT: $0");

exit(0);

