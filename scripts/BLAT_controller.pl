#!/usr/local/bin/perl5.8.0 -w
#
# Last edited by: $Author: klh $
# Last edited on: $Date: 2011-03-21 11:01:49 $


use lib $ENV{'CVS_DIR'};

use strict;
use Wormbase;
use Getopt::Long;
use File::Copy;
use File::Path;
use Log_files;
use Storable;
use Sequence_extract;
use LSF RaiseError => 0, PrintError => 1, PrintOutput => 0;
use LSF::JobManager;

my ($test, $database, $debug);
my ($mask, $dump_dna, $run, $postprocess, $load, $process, $intron);
my @types;
my $all;
my $store;
my ($species, $qspecies, $nematode);

GetOptions (
	    'debug:s'     => \$debug,
	    'test'        => \$test,
	    'database:s'  => \$database,
	    'store:s'     => \$store,
	    'species:s'   => \$species,  #target species (ie genome seq)
	    'mask'        => \$mask,
	    'dump'        => \$dump_dna,
	    'process'     => \$process,
	    'run'         => \$run,
	    'postprocess' => \$postprocess,
	    'load'        => \$load,
	    'types:s'     => \@types,
	    'all'         => \$all,
	    'qspecies:s'  => \$qspecies,    #query species (ie cDNA seq)
	    'intron'      => \$intron
	   );

my $wormbase;
if( $store ) {
  $wormbase = retrieve( $store ) or croak("cant restore wormbase from $store\n");
}
else {
  $wormbase = Wormbase->new( -debug   => $debug,
			     -test     => $test,
			     -organism => $species
			   );
}


$database    = $wormbase->autoace unless $database;
$species  = $wormbase->species;

my $log      = Log_files->make_build_log($wormbase);
my $wormpub  = $wormbase->wormpub;
my $blat_dir = $wormbase->blat;
my $seq_obj  = Sequence_extract->invoke($database, undef, $wormbase) if $intron;

#The mol_types available for each species is different
#defaults lists - can be overridden by -types

my %mol_types = ( 'elegans'          => [qw( EST mRNA ncRNA OST tc1 RST )],
		  'briggsae'         => [qw( mRNA EST )],
		  'remanei'          => [qw( mRNA EST )],
		  'brenneri'         => [qw( mRNA EST )],
		  'japonica'         => [qw( mRNA EST )],
		  'heterorhabditis'  => [qw( mRNA EST )],
		  'brugia'           => [qw( mRNA EST )],
		  'pristionchus'     => [qw( mRNA EST )],
		  'nematode'         => [qw( EST )],
		  'nembase'          => [qw( EST )],
		  'washu'            => [qw( EST )],

				);

my @nematodes = qw(nematode washu nembase);

#remove other species if single one specified
if( $qspecies ){
  if( grep(/$qspecies/, keys %mol_types)) {
    foreach (keys %mol_types){
      delete $mol_types{$_} unless ($qspecies eq $_);
    }
  } else {
    $log->log_and_die("we only deal in certain species!\n");
  }
  @nematodes = ();
}
	
#set specific mol_types if specified.
if(@types) {
  foreach (keys %mol_types){
    ($mol_types{$_}) = [(@types)];
  }
  @nematodes = ();
}


# mask the sequences based on Feature_data within the species database (or autoace for elegans.)
if( $mask ) {
  foreach my $qspecies ( keys %mol_types ) {
    next if (grep /$qspecies/, @nematodes);
    foreach my $moltype (@{$mol_types{$qspecies}}) {
      #transcriptmasker is designed to be run on a sinlge species at a time.
      #therefore this uses the query species ($qspecies) as the -species parameter so that 
      #transcriptmasker creates a different Species opbject and gets the correct paths! 
      $wormbase->bsub_script("transcriptmasker.pl -species $qspecies -mol_type $moltype", $qspecies, $log);
    }
  }
}

# Now make blat target database using autoace (will be needed for all possible blat jobs)

&dump_dna if $dump_dna;


# run all blat jobs on cluster ( eg cbi4 )
if ( $run ) {

  # run other species
  foreach my $species (keys %mol_types) {
    # skip own species
    next if $species eq $wormbase->species;

    foreach my $moltype( @{$mol_types{$species}} ) {
      my $seq_dir = join("/", $wormbase->basedir, "cDNA", $species );
      &check_and_shatter( $seq_dir, "$moltype.masked" );

      foreach my $seq_file (glob("${seq_dir}/${moltype}.masked*")) {
        my $chunk_num = 1; 
        if ($seq_file =~ /_(\d+)$/) {
          $chunk_num = $1;
        }
        
        my $cmd = "bsub -E \"test -d /software/worm\" -o /dev/null -e /dev/null -J ${species}_${moltype}_${chunk_num} \"/software/worm/bin/blat/blat -noHead -t=dnax -q=dnax ";
        $cmd .= $wormbase->genome_seq ." $seq_file ";
        $cmd .= $wormbase->blat."/${species}_${moltype}_${chunk_num}.psl\"";
        $wormbase->run_command($cmd, $log);
      }
    }
  }


  # run own species.
  foreach my $moltype (@{$mol_types{$wormbase->species}} ){
    my $seq_dir = $wormbase->maskedcdna;
    &check_and_shatter($wormbase->maskedcdna, "$moltype.masked");
    foreach my $seq_file (glob ($seq_dir."/$moltype.masked*")) {
      my $chunk_num = 1; 
      if ($seq_file =~ /_(\d+)$/) {
        $chunk_num = $1;
      }
      
      my $cmd = "bsub -E \"test -d /software/worm\" -o /dev/null -e /dev/null -J ".$wormbase->species . "_${moltype}_${chunk_num} \"/software/worm/bin/blat/blat -noHead ";
      $cmd .= $wormbase->genome_seq ." $seq_file ";
      $cmd .= $wormbase->blat."/".$wormbase->species."_${moltype}_${chunk_num}.psl\"";
      $wormbase->run_command($cmd, $log);	
    }
  }
}

if( $postprocess ) {
  # merge psl files and convert to ace format
  $log->write_to("merging PSL files \n");
  my $blat_dir = $wormbase->blat;
  foreach my $species (keys %mol_types) {
    foreach my $moltype ( @{$mol_types{$species}}){
      $wormbase->run_command("cat $blat_dir/${species}_${moltype}_* |sort -u  > $blat_dir/${species}_${moltype}_out.psl", $log);
    }
  }
}

if ( $process ) {
  
  my $lsf1 = LSF::JobManager->new();
  foreach my $species (keys %mol_types) {
    foreach my $type (@{$mol_types{$species}} ) {
      #create virtual objects
      $log->write_to("Submitting $species $type for virtual procesing\n");
      
      my $job_name = "worm_".$wormbase->species."_blat";

      my $cmd;
      # only get data for confirmed introns from same-species alignmenrs
      if ($species eq $wormbase->species and $intron) {
        $cmd = $wormbase->build_cmd("blat2ace.pl -virtual -intron -type $type -qspecies $species");
      } else {
        $cmd = $wormbase->build_cmd("blat2ace.pl -virtual -type $type -qspecies $species");
      }
      if ($test) {
        $cmd .= " -test";
      }
      if ($debug) {
        $cmd .= " -debug $debug";
      }

      # ask for a file size limit of 2 Gb and a memory limit of 4 Gb
      my @bsub_options = (-F => "2000000", 
			  -M => "4000000", 
			  -R => "\"select[mem>4000] rusage[mem=4000]\"",
			  -J => $job_name);
      $lsf1->submit(@bsub_options, $cmd);
      
    }
  }
  $lsf1->wait_all_children( history => 1 );
  $log->write_to("All blat2ace runs have completed!\n");
  for my $job ( $lsf1->jobs ) {    # much quicker if history is pre-cached
    $log->error("$job exited non zero\n") if $job->history->exit_status != 0;
  }
  $lsf1->clear;   
  
  if($intron) {
    $log->write_to("confirming introns . . \n");
    #only do for self species matches
    foreach my $type (@{$mol_types{$wormbase->species}} ) {
      my $virt_hash = &confirm_introns($wormbase->species, $type);
      my $vfile = "$blat_dir/virtual_objects." . $wormbase->species . ".ci.${type}." . $wormbase->species . ".ace";
      open(my $vfh, ">$vfile") or $log->log_and_die("Could not open $vfile for writing\n");

      foreach my $tname (keys %$virt_hash) {
        print $vfh "\nSequence : \"$tname\"\n";
        foreach my $child (sort { my ($na) = ($a =~ /_(\d+)$/); my ($nb) = ($b =~ /_(\d+)$/); $na <=> $nb } keys %{$virt_hash->{$tname}}) {
          printf $vfh "S_Child Feature_data %s %d %d\n", $child, @{$virt_hash->{$tname}->{$child}};
        }
      }
      close($vfh);
    }
  }
}


if( $load ) {
  foreach my $species (keys %mol_types){
    $log->write_to("Loading $species BLAT data\n");
    foreach my $type (@{$mol_types{$species}}){
      $log->write_to("\tloading BLAT data - $type\n"); 

      # virtual objs
      my $file =  "$blat_dir/virtual_objects." . $wormbase->species . ".blat.$type.$species.ace";
      if (-e $file) {
	$wormbase->load_to_database( $database, $file,"virtual_objects_$type", $log);
      } else {
	$log->write_to("\tskipping $file\n"); 
      }

      # confirmed introns - will only be any for within-species alignments
      if ($species eq $wormbase->species) {

        my ($in_v_tag, $in_v_file) = ("blat_introns_virtual$type",  "$blat_dir/virtual_objects.".$wormbase->species.".ci.$type.$species.ace");
        my ($in_tag, $in_file) = ("blat_good_introns_${type}", "$blat_dir/".$wormbase->species.".good_introns.$type.ace");

        if (-e $in_v_file and -e $in_file) {
          $wormbase->load_to_database($database, $in_v_file, $in_v_tag, $log);
          $wormbase->load_to_database($database, $in_file, $in_tag, $log);
        } else {
          $log->write_to("\tskipping ci file(s) for $type because one or both is missing\n"); 
        }
      }
        
      # BLAT results
      $file = "$blat_dir/".$wormbase->species.".blat.${species}_$type.ace";
      $wormbase->load_to_database($database, $file, "blat_${species}_${type}_data", $log,1);
    }
  }
}


#confirm introns
sub confirm_introns {
  my ($qspecies, $type) = @_;
  
  # open the output files
  open (my $good_fh, ">$blat_dir/".$wormbase->species.".good_introns.$type.ace") or die "$!";
  open (my $bad_fh,  ">$blat_dir/".$wormbase->species.".bad_introns.$type.ace")  or die "$!";
  
  my ($link,@introns, %seqlength, %virtuals);
   
  $/ = "";
  	
  open (CI, "<$blat_dir/".$wormbase->species.".ci.${qspecies}_${type}.ace")  
      or $log->log_and_die("Cannot open $blat_dir/".$wormbase->species.".ci.${qspecies}_${type}.ace $!\n");

  while (<CI>) {
    next unless /^\S/;
    if (/Sequence : \"(\S+)\"/) {
      $link = $1;

      if (not exists $seqlength{$link}) {
        $seqlength{$link} = length($seq_obj->Sub_sequence($link));
      }

      @introns = split /\n/, $_;
      
      # evaluate introns #
      $/ = "";
      foreach my $test (@introns) {
	if ($test =~ /Confirmed_intron/) {
          my @f = split /\s+/, $test;
	  
	  #######################################
	  # get the donor and acceptor sequence #
	  #######################################
	            
          my ($tstart, $tend, $strand) = ($f[1], $f[2], 1);
          if ($tend < $tstart) {
            ($tstart, $tend, $strand) = ($tend, $tstart, -1);
          }

          
          my $start_splice = $seq_obj->Sub_sequence($link,$tstart - 1, 2);
          my $end_splice   = $seq_obj->Sub_sequence($link,$tend - 2,2);
	  
          print "Coords start => $tstart, end $tend\n" if $debug;
	  
	  ##################
	  # map to S_child #
	  ##################
          my $binsize = 100000;

          my $bin = 1 +  int( $tstart / $binsize );
          my $bin_start = ($bin - 1) * $binsize + 1;
          my $bin_end   = $bin_start + $binsize - 1;
          
          if ($bin_end > $seqlength{$link}) {
            $bin_end = $seqlength{$link};
          }
          my $bin_of_end = 1 +  int( $tend / $binsize );
          
          if ($bin == $bin_of_end or
              ($bin == $bin_of_end - 1 and $tend - $bin_end < ($binsize / 2))) {
            # both start and end lie in the same bin or adjacent bins - okay
            $tstart = $tstart - $bin_start + 1;
            $tend = $tend - $bin_start + 1;

            if ($strand < 0) {
              ($tstart, $tend) = ($tend, $tstart);
            }
          } else {
            # intron has too great a span; skip it. 
            next;
          }
          
          my $virtual = "Confirmed_intron_${type}:${link}_${bin}";
      
          if (not exists $virtuals{$link}->{$virtual}) {
            $virtuals{$link}->{$virtual} = [$bin_start, $bin_end];
          }
          
          if ( ( (($start_splice eq 'gt') || ($start_splice eq 'gc')) && ($end_splice eq 'ag')) ||
               (  ($start_splice eq 'ct') && (($end_splice eq 'ac') || ($end_splice eq 'gc')) ) ) {	 

            print $good_fh "Feature_data : \"$virtual\"\n";
            
            # check to see intron length. If less than 25 bp then mark up as False
            # dl 040414
            
            if (abs($tend - $tstart) <= 25) {
              print $good_fh "Confirmed_intron $tstart $tend False $f[4]\n\n";
            } else {
              if ($type eq "mRNA"){
                print $good_fh "Confirmed_intron $tstart $tend cDNA $f[4]\n\n";
              }
              else {
                print $good_fh "Confirmed_intron $tstart $tend EST $f[4]\n\n";
              }
            }
          }
          else {
            if ($type eq "mRNA"){
              print $bad_fh "Feature_data : \"$virtual\"\n";
              print $bad_fh "Confirmed_intron $tstart $tend cDNA $f[4]\n\n";		
            }
            else {
              print $bad_fh "Feature_data : \"$virtual\"\n";
              print $bad_fh "Confirmed_intron $tstart $tend EST $f[4]\n\n";
            }
          }
        }
      }
    }
  }
  close(CI);
  close($good_fh);
  close($bad_fh);
  
  return \%virtuals;
}


$log->mail;
exit(0);


###############################################################################################################

sub check_and_shatter {
  my $dir = shift;
  my $file = shift;
  
  unless( -e "$dir/$file" ) {
    $log->write_to("$file doesnt exist - hopefully already shattered for other species\n");
    my @shatteredfiles = glob("$dir/$file*");
    if(scalar @shatteredfiles == 0){
      $log->log_and_die("shattered files also missing - not good");
    }
  }else {		
    my $seq_count = qx(grep -c '>' $dir/$file);
    if( $seq_count > 10000) {
      $wormbase->run_script("shatter $dir/$file 10000 $dir/$file", $log);
      $wormbase->run_command("rm -f $dir/$file", $log);
    }
  }
}

#############################################################################
# dump_dna                                                                  #
# gets data out of autoace/camace, runs tace query for chromosome DNA files #
# and chromosome link files.                                                #
#############################################################################

sub dump_dna {
  my @files = glob($wormbase->chromosomes."/*.dna");
  push(@files,glob($wormbase->chromosomes."/*.fa"));
  
  open(GENOME,">".$wormbase->autoace."/genome_seq") or $log->log_and_die("cant open genome sequence file".$wormbase->autoace."/genome_seq: $!\n");
  foreach (@files){
    next if (/supercontig/ && scalar @files>1); # don't touch this
    print GENOME "$_\n";
  }
  close GENOME;
}
__END__

