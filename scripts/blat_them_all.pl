#!/software/bin/perl -w
#
# blat_them_all.pl
# 
# by Kerstin Jekosch
#
# Gets sequences ready for blatting, blats sequences, processes blat output, makes confirmed introns
# and virtual objects to hang the data onto
#
# Last edited by: $Author: pad $
# Last edited on: $Date: 2008-03-10 13:28:00 $


use strict;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use IO::Handle;
use Getopt::Long;
use Carp;
use Log_files;
use Storable;

##############################
# Misc variables and paths   #
##############################

my ($help, $debug, $test, $verbose , $dbpath, $species);
my ($est, $mrna, $ncrna, $ost, $nematode, $embl,, $washu, $nembase, $blat, $tc1);
my ($process, $virtual, $dump, $camace, $fine, $nointron);
my $store;

#########################
# Command line options  #
#########################

GetOptions ("help"       => \$help,
            "debug:s"    => \$debug,
	    "test"       => \$test,
	    "verbose"    => \$verbose,
	    "species:s"  => \$species,
	    "database"   => \$dbpath,
	    "store:s"    => \$store,
	    "est"        => \$est,
	    "mrna"       => \$mrna,
	    "ncrna"      => \$ncrna,
	    "ost"        => \$ost,
	    "nematode"   => \$nematode,
	    "embl"       => \$embl,
	    "tc1"        => \$tc1,
	    "nembase"    => \$nembase,
	    "washu"      => \$washu,
	    "dump"       => \$dump,
	    "blat"       => \$blat,
	    "process"    => \$process,
	    "virtual"    => \$virtual,
	    "camace"     => \$camace,
	    "fine"       => \$fine,
	    "nointron"   => \$nointron
	    );


########################################
# command-line options & ramifications #
########################################

my $wormbase;
if( $store ) {
  $wormbase = retrieve( $store ) or croak("cant restore wormbase from $store\n");
}
else {
  $wormbase = Wormbase->new( -debug   => $debug,
			     -test    => $test,
			     -organism => $species
			   );
}
my $log         = Log_files->make_build_log($wormbase);
my $errors      = 0;
my $bin         = $ENV{'CVS_DIR'};
my $wormpub     = $wormbase->wormpub;

# database location
$dbpath = $wormbase->autoace unless $dbpath;

our $blat_dir   = "$dbpath/BLAT";             # default BLAT directory, can get changed if -camace used
our %homedb;                                  # for storing superlink->lab connections
our $giface     = $wormbase->giface;
our %word = (
	     est      => 'BLAT_EST',
	     mrna     => 'BLAT_mRNA',
	     ncrna    => 'BLAT_ncRNA',
	     embl     => 'BLAT_EMBL',
	     nematode => 'BLAT_NEMATODE',
	     ost      => 'BLAT_OST',
	     tc1      => 'BLAT_TC1',
	     nembase  => 'BLAT_NEMBASE', 
	     washu    => 'BLAT_WASHU'
	     );

our $seq  = $wormbase->genome_seq;

# Help pod documentation
&usage("Help") if ($help);

# Exit if no dump/process/blat/virtual process option chosen
&usage(1) unless ($dump || $process || $blat || $virtual); 

# Exit if no data type choosen [EST|mRNA|EMBL|NEMATODE|OST] (or -dump not chosen)
&usage(2) unless ($est || $mrna || $ncrna || $embl || $tc1 || $nematode || $ost || $washu || $nembase || $dump); 

# Exit if multiple data types choosen [EST|mRNA|ncRNA|EMBL|NEMATODE|OST|WASHU|NEMBASE]
# ignore if -dump is being run
unless($dump){
  my $flags = 0;
  $flags++ if $est;
  $flags++ if $ost;
  $flags++ if $mrna;
  $flags++ if $ncrna;
  $flags++ if $embl;
  $flags++ if $tc1;
  $flags++ if $nematode;
  $flags++ if $nembase;
  $flags++ if $washu;
  &usage(3) if ($flags > 1);
}

# Exit if -fine option is being used without -mrna
&usage(4) if ($fine && !$mrna);


# assign type variable
my $data;
($data = 'est')      if ($est);
($data = 'ost')      if ($ost);
($data = 'mrna')     if ($mrna);
($data = 'ncrna')    if ($ncrna);
($data = 'embl')     if ($embl);
($data = 'tc1')      if ($tc1);
($data = 'nematode') if ($nematode);
($data = 'nembase')  if ($nembase);
($data = 'washu')    if ($washu);


# Select the correct set of query sequences for blat
my $query = $wormbase->blat."/";
$query   .= 'elegans_ESTs.masked'  if ($est);      # EST data set
$query   .= 'elegans_OSTs'         if ($ost);      # OST data set
$query   .= 'elegans_TC1s'         if ($tc1);      # TC1 data set
$query   .= 'elegans_mRNAs.masked' if ($mrna);     # mRNA data set
$query   .= 'elegans_ncRNAs.masked'if ($ncrna);    # ncRNA data set
$query   .= 'other_nematode_ESTs'  if ($nematode); # ParaNem EST data set
$query   .= 'elegans_embl_cds'     if ($embl);     # Other CDS data set, DNA not peptide!
$query   .= 'nembase_nematode_contigs' if ($nembase);  # Contigs from NemBase
$query   .= 'washu_nematode_contigs' if ($washu);  # Contigs from Nematode.net - John Martin <jmartin@watson.wustl.edu>


###########################################################################
#                                                                         #
#                        MAIN PART OF PROGRAM                             #
#                                                                         #
###########################################################################


####################################################################
# process blat output (*.psl) file and convert results to acefile
# by running blat2ace
# Then produce confirmed introns files
#####################################################################

if ($process) {

    my $runtime = $wormbase->runtime;
    print "Mapping blat data to autoace\n" if ($verbose);      
    $log->write_to("$runtime: Processing blat ouput file, running blat2ace.pl\n");
    
    # treat slightly different for nematode data (no confirmed introns needed)
    if ( ($nematode) || ($tc1) || ($embl) || ($ncrna) || ($washu) || ($nembase)) {
	$wormbase->run_script("blat2ace.pl -$data"); 
    }
    elsif($camace){
	$wormbase->run_script("blat2ace.pl -$data -intron -camace"); 	
    }
    else {
	$wormbase->run_script("blat2ace.pl -$data -intron"); 
    }

    $runtime = $wormbase->runtime;
    print "Producing confirmed introns in databases\n\n" if $verbose;
    $log->write_to("$runtime: Producing confirmed introns in databases\n");


    # produce confirmed introns for all but nematode, tc1, embl and ncRNA data
    unless( $nointron ){
      unless ( ($nematode) || ($tc1) || ($embl) || ($ncrna)|| ($washu) || ($nembase) ) {
		print "Producing confirmed introns using $data data\n" if $verbose;
		&confirm_introns('autoace',"$data");
      }
    }
  }


#########################################
# produce files for the virtual objects #
#########################################

if ($virtual) {
    my $runtime = $wormbase->runtime;
    $log->write_to("$runtime: Producing $data files for the virtual objects\n");
    
    print "// Assign laboratories to superlinks*\n";
    # First assign laboratories to each superlink object (stores in %homedb)
    &virtual_objects_blat($data);
}


##############################
# Clean up and say goodbye   #
##############################

$log->mail;
exit(0);





#################################################################################
#                                                                               #
#                     T H E    S U B R O U T I N E S                            #
#                                                                               #
#################################################################################


sub confirm_introns {

  my ($db,$data) = @_;
  local (*GOOD,*BAD,*SEQ);
  
  # open the output files
  open (GOOD, ">$blat_dir/$db.good_introns.$data.ace") or die "$!";
  open (BAD,  ">$blat_dir/$db.bad_introns.$data.ace")  or die "$!";
  
  my ($link,@introns,$dna,$switch,$tag);
  
  ($tag = "cDNA") if ($mrna || $embl);
  ($tag = "EST")  if ($est || $ost); 
  
  
  $/ = "";
  open (CI, "<$blat_dir/${db}.ci.${data}.ace")      or die "Cannot open $blat_dir/$db.ci.$data.ace $!\n";
  while (<CI>) {
    next unless /^\S/;
    if (/Sequence : \"(\S+)\"/) {
      $link = $1;
      print "Sequence : $link\n";
      @introns = split /\n/, $_;
      
      # get the link sequence #
      print "Extracting DNA sequence for $link\n";
      undef ($dna);
      
      open(SEQ, "<$blat_dir/autoace.fa") || &usage(5);
      $switch = 0;
      $/ = "\n";
      
      # added shortcuts next & last to speed this section
      
      while (<SEQ>) {
	if (/^\>$link$/) {
	  $switch = 1;
	  next;
	}
	elsif (/^(\w+)$/) {
	  if ($switch == 1) {
	    chomp;
	    $dna .= $1;
	  }			
	}
	elsif ($switch == 1) {
	  $switch = 0;
	  last;
	}
	else { 
	  $switch = 0;
	}
      }
      close SEQ;
      
      print "DNA sequence is " . length($dna) . " bp long.\n";
      
      # evaluate introns #
      $/ = "";
      foreach my $test (@introns) {
	if ($test =~ /Confirmed_intron/) {
	    my @f = split / /, $test;
	  
	  #######################################
	  # get the donor and acceptor sequence #
	  #######################################
	  
	    my ($first,$last,$start,$end,$pastfirst,$prelast);
	    if ($f[1] < $f[2]) {
		($first,$last,$pastfirst,$prelast) = ($f[1]-1,$f[2]-1,$f[1],$f[2]-2);
	    }
	    else {
		($first,$last,$pastfirst,$prelast) = ($f[2]-1,$f[1]-1,$f[2],$f[1]-2);
	    }	
	    
	    $start = substr($dna,$first,2);
	    $end   = substr($dna,$prelast,2);
	  
#	    print "Coords start $f[1] => $start, end $f[2] => $end\n";
	  
	  ##################
	  # map to S_child #
	  ##################
	  
	  my $lastvirt = int((length $dna) /100000) + 1;
	  my ($startvirt,$endvirt,$virtual);
	  if ((int($first/100000) + 1 ) > $lastvirt) {
	    $startvirt = $lastvirt;
	  }
	  else {
	    $startvirt = int($first/100000) + 1;
	  }
	  if ((int($last/100000) + 1 ) > $lastvirt) {
	    $endvirt = $lastvirt;
	  }
	  else {
	    $endvirt = int($first/100000) + 1;
	  }
	  
	  if ($startvirt == $endvirt) { 
	    $virtual = "Confirmed_intron_EST:" .$link."_".$startvirt     if ($est);
	    $virtual = "Confirmed_intron_OST:" .$link."_".$startvirt     if ($ost);
	    $virtual = "Confirmed_intron_mRNA:".$link."_".$startvirt     if ($mrna);
	    $virtual = "Confirmed_intron_EMBL:".$link."_".$startvirt     if ($embl);
	  }
	  elsif (($startvirt == ($endvirt - 1)) && (($last%100000) <= 50000)) {
	    $virtual = "Confirmed_intron_EST:" .$link."_".$startvirt     if ($est);
	    $virtual = "Confirmed_intron_OST:" .$link."_".$startvirt     if ($ost);
	    $virtual = "Confirmed_intron_mRNA:".$link."_".$startvirt     if ($mrna);
	    $virtual = "Confirmed_intron_EMBL:".$link."_".$startvirt     if ($embl);
	  }
	  
	  #################
	  # check introns #
	  #################
	  
	    my $firstcalc = int($f[1]/100000);
	    my $seccalc   = int($f[2]/100000);
	    print STDERR "Problem with $test\n" unless (defined $firstcalc && defined $seccalc); 
	    my ($one,$two);
	    if ($firstcalc == $seccalc) {
		$one = $f[1]%100000;
		$two = $f[2]%100000;
	    }
	    elsif ($firstcalc == ($seccalc-1)) {
		$one = $f[1]%100000;
		$two = $f[2]%100000 + 100000;
		print STDERR "$virtual: $one $two\n";
	    }
	    elsif (($firstcalc-1) == $seccalc) {
		$one = $f[1]%100000 + 100000;
		$two = $f[2]%100000;
		print STDERR "$virtual: $one $two\n";
	    } 
	    print STDERR "Problem with $test\n" unless (defined $one && defined $two); 
	    
	    if ( ( (($start eq 'gt') || ($start eq 'gc')) && ($end eq 'ag')) ||
		 (  ($start eq 'ct') && (($end eq 'ac') || ($end eq 'gc')) ) ) {	 
		print GOOD "Feature_data : \"$virtual\"\n";
		
		# check to see intron length. If less than 25 bp then mark up as False
		# dl 040414
		
		if (abs ($one - $two) <= 25) {
		    print GOOD "Confirmed_intron $one $two False $f[4]\n\n";
		}
		else {
		    print GOOD "Confirmed_intron $one $two $tag $f[4]\n\n";
		}
	    }
	    else {
		print BAD "Feature_data : \"$virtual\"\n";
		print BAD "Confirmed_intron $one $two $tag $f[4]\n\n";		
	    }
	}
    }
  }
}
  close CI;
  
  close GOOD;
  close BAD;
  
}


#############################
# virtual object generation #
#############################

sub virtual_objects_blat {
    
  my ($data) = shift;
  local (*OUT_autoace_homol);
  local (*OUT_autoace_feat);
  my ($name,$length,$total,$first,$second,$m,$n);
  
  # autoace
  open (OUT_autoace_homol, ">$blat_dir/virtual_objects.".$wormbase->species.".blat.$data.ace") or die "$!";
  open (OUT_autoace_feat,  ">$blat_dir/virtual_objects.".$wormbase->species.".ci.$data.ace")   or die "$!";
  
  open (ACE, "<$blat_dir/chromosome.ace") || die &usage(11);
  while (<ACE>) {
    if (/Subsequence\s+\"(\S+)\" (\d+) (\d+)/) {
      $name   = $1;
      $length = $3 - $2 + 1;
      $total = int($length/100000) +1;
      # autoace
      print OUT_autoace_homol "Sequence : \"$name\"\n";
      print OUT_autoace_feat  "Sequence : \"$name\"\n";

      for ($n = 0; $n <= $total; $n++) {
	$m      = $n + 1;
	$first  = ($n*100000) + 1;
	$second = $first + 149999;
	if (($length - $first) < 100000) {
	  $second = $length;
	  # autoace
	  print OUT_autoace_homol "S_child Homol_data $word{$data}:$name"."_$m $first $second\n";
	  print OUT_autoace_feat  "S_child Feature_data Confirmed_intron_$data:$name"."_$m $first $second\n";

	  last;
	}					
	else {
	  ($second = $length) if ($second >  $length);
	  # autoace
	  print OUT_autoace_homol "S_child Homol_data $word{$data}:$name"."_$m $first $second\n";
	  print OUT_autoace_feat  "S_child Feature_data Confirmed_intron_$data:$name"."_$m $first $second\n";
}
      }
      print OUT_autoace_homol "\n";
      print OUT_autoace_feat  "\n";

    }
  }
  close ACE;
  close OUT_autoace_homol;
  close OUT_autoace_feat;
  
  # clean up if you are dealing with parasitic nematode conensus or TC1 insertion data
  # dl 040315 - this is crazy. we make all of the files and then delete the ones we don't want.
  #             don't rock the boat...

  if ( ($data eq "nematode") || ($data eq "tc1") || ($data eq "ncrna") || ($data eq "embl") || ($data eq "washu") || ($data eq "nembase")) {
    unlink ("$blat_dir/virtual_objects.".$wormbase->species.".ci.$data.ace");
  }

}

##################################################################################################


#################################################################################################
#
# Usage / Help subroutine
#
##################################################################################################


sub usage {
    my $error = shift;

    if ($error eq "Help") {
      # Normal help menu
      system ('perldoc',$0);
      exit (0);
    }

    if ($error == 1) {
      # no option supplied
      print "\nNo process option choosen [-dump|-blat|-process|virtual]\n";
      print "Run with one of the above options\n\n";
      exit(0);
    }
    elsif ($error == 2) {
      # No data-type choosen
      print "\nNo data option choosen [-est|-mrna|-ost|-embl|-nematode|-washu|-nembase]\n";
      print "Run with one of the above options\n\n";
      exit(0);
    }
    elsif ($error == 3) {
      # 'Multiple data-types choosen
      print "\nMultiple data option choosen [-est|-mrna|-ost|-nematode|-embl|-washu|-nembase]\n";
      print "Run with one of the above options\n\n";
      exit(0);
    }
    elsif ($error == 4) {
      # -fine used without -mrna
      print "-fine can only be specified if you are using -mrna\n\n";
      exit(0);
    }
    elsif ($error == 5) {
      # 'autoace.fa' file is not there or unreadable
      print "\nThe WormBase 'autoace.fa' file you does not exist or is non-readable.\n";
      print "Check File: '${blat_dir}/autoace.fa'\n\n";
      exit(0);
    }
    elsif ($error == 6) {
      # BLAT failure
      print "BLAT failure.\n";
      print "Whoops! you're going to have to start again.\n\n";
      exit(0);
    }
    elsif ($error == 11) {
      # 'superlinks.ace' file is not there or unreadable
      print "\nThe WormBase 'superlinks.ace' file you does not exist or is non-readable.\n";
      print "Check File: '${blat_dir}/superlinks.ace'\n\n";
      exit(0);
    }
    elsif ($error == 0) {
      # Normal help menu
      exec ('perldoc',$0);
    }
}

######################################################################################################


##########################################################################################################

# Old comments from header part of script
#
# 16.10.01 Kerstin Jekosch
# 17.10.01 kj: modified to get everything onto wormsrv2 and to include an mRNA and parasitic nematode blatx option
# 26.11.01 kj: runs everything for autoace AND camace now
# 13.11.01 kj: added some file removers to tidy up at the end
# 14.11.01 kj: added option to just produce virtual objects
# 01.02.02 dl: added option to search miscPep file
# 01.02.02 dl: uncommented report logging & mail routines
# 01.02.02 dl: routine to convert '-' -> 'N' needs to be within the same BLOCK as the tace command
#            : else you get a zero length fasta file each time and the confirm intron routines fail
# 02.02.21 dl: typos in the naming of the confirmed_intron virtual objects
# 02.04.08 dl: old style logging for autoace.fa check, prevented complete run of subs
#



__END__

=pod

=head2   NAME - blat_them_all.pl

=head1 USAGE

=over 4

=item  blat_them_all.pl -options

=back

A wrapper script to generate blat data by: 

1) getting target sequence out of autoace

2) blatting it against all ESTs/OSTs, mRNAs, and CDSs from EMBL entries

3) Processing blat output files, and mapping hits back to autoace/camace 

4) Producing confirmed introns

5) Producing virtual objects to 'hang' the data onto

All output is stored in /wormsrv2/autoace/BLAT/ (or /nfs/disk100/wormpub/DATABASES/camace/BLAT/ if -camace
is specified)

blat_them_all mandatory arguments:

=over 4

=item -est

run everything for ESTs

=back

or

=item -mrna

run everything for mRNAs

=back

or

=item -ncrna

run everything for ncRNAs

=back

or
=item -embl

run everything for the CDSs of non-WormBase gene predictions in EMBL

=back

or

=item -nematode   

run everything for non-C.elegans nematode ESTs

=back

or 

=item -ost   

run everything for OST data

=back

or 

=item -nembase

run everything for NemBase contigs

=back

or 

=item -washu

run everything for WashU Nematode.net - John Martin <jmartin@watson.wustl.edu> contigs

=back



blat_them_all optional arguments:

=item -dump      

start by first dumping out target chromosome sequences and acefiles from autoace/camace

=back

=item -blat      

start with blatting (i.e. autoace.fa & chromosome.ace already present)

=back

=item -process   

start later by processing (and sorting/mapping) existing *.psl file

=back

=item -camace    

Use nfs/disk100/wormpub/DATABASES/camace rather than the default /wormsrv2/autoace

=back

=item -fine      

Forces use of new -fine option in blat, only in conjunction with -mrna

=back

=item -verbose   

Show more output to screen (useful when running on command line)

=back

=item -debug <user> 

Send output only to user and not to everyone in group

=back

=item -help      

This help

=back

Script written by Kerstin Jekosch with heavy rewrite by Keith Bradnam

=cut



