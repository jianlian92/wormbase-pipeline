#!/usr/local/bin/perl5.8.0 -w
#
# make_autoace
# dl1/ag3 & others
#
# Usage : make_autoace [-options]
#
# This makes the autoace database from its composite sources.
#
# Last edited by: $Author: pad $
# Last edited on: $Date: 2015-01-14 09:53:41 $

use strict;
use lib  $ENV{'CVS_DIR'};
use Wormbase;
use IO::Handle;
use Getopt::Long;
use Cwd;
use File::Copy;
use File::Path;
use Log_files;
use Storable;

#################################
# Command-line options          #
#################################

our ($help, $debug, $test, $species);
my $store;
my( $all, $parse, $init, $tmpgene, $pmap, $chromlink, $check, $allcmid, $reorder );

GetOptions ("help"         => \$help,
            "debug=s"      => \$debug,
	    "test"         => \$test,
	    "store:s"      => \$store,
	    "parse"        => \$parse,
	    "init"         => \$init,
	    "tmpgene"      => \$tmpgene,
	    "pmap"         => \$pmap,
	    "chromlink"    => \$chromlink,
	    "check"        => \$check,
	    "allcmid"      => \$allcmid,
	    "reorder"      => \$reorder,
	    "species:s"	   => \$species,
	   );

$all = 1 unless( $init or $parse or $tmpgene or $pmap or $chromlink or $check or $allcmid or $reorder ) ;

# Display help if required
&usage("Help") if ($help);


###################################
# Check command-line arguments    #
###################################

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

$species = $wormbase->species;

# Exit if no database specified
# database/file paths and locations
my $basedir     = $wormbase->basedir;

my $autoacedir  = $wormbase->orgdb;
my $wormbasedir = "$autoacedir/acefiles/primaries";
my $configfile  = "$basedir/autoace_config/".$wormbase->species.".config";
my $dbpath = $autoacedir;

# make log files
my $log = Log_files->make_build_log($wormbase);

##################
# misc variables # 
##################

my $WS_current    = $wormbase->get_wormbase_version;
my $WS_version    = $wormbase->get_wormbase_version_name;
my @filenames; # for storing contents of autoace_config

my $tace   = $wormbase->tace;
my $giface = $wormbase->giface;

my $errors = 0; # for tracking system call related errors

# start doing stuff
#&mail_reminder;

#Set up correct database structure if it doesn't exist
&createdirs;	

# Parse config file
&parseconfig if ( $all or $parse );

# Re-initialize the database
# Re-initializing database is more complex as the .acefiles will be spread over a number of
# directories - use the config file to find them all
&reinitdb() if ( $all or $init );

if($wormbase->species eq 'elegans') {
	# remove temp genes
	&remove_pariah_gene() if( $all or $tmpgene );

	# remove tiling array data from autoace.
	&remove_tiling_data;

	# Read in the physical map and make all maps
	&physical_map_stuff() if( $all or $pmap );

	#check new build
	&check_make_autoace if ( $all or $check );

	#write cosmid seq file
	&allcmid if ( $allcmid );

	#reorder exons
	$wormbase->run_script("reorder_exons.pl", $log ) if( $all or $reorder );
}

#finish
$log->mail;
exit (0);



##############################################################
#
# Subroutines
#
##############################################################


###################################################
# Subroutine for writing to a given database    ###
###################################################

sub DbWrite {
    my ($command,$exec,$dir,$name)=@_;
    open (WRITEDB,"| $exec $dir") or $log->log_and_die("$name DbWrite failed\n");
    print WRITEDB $command;
    close WRITEDB;
}


################################################
# Remove Bad gene predictions from the database

sub remove_pariah_gene {
  
  $log->write_to($wormbase->runtime." : starting pariah gene subroutine\n");

  my $command  = "query find elegans_CDS method = hand_built\nkill\n";                                  # Any objects with Method "hand_build"
  $command    .= "query find elegans_CDS temp*\nkill\n";                                                # Any objects "temp*"
  $command    .= "query find elegans_CDS RNASEQ*\nkill\n";                                                # Any objects "temp*"
  $command    .= "query find CDS where Method = Genefinder AND Species = \"*elegans\"\nkill\n";         # Any elegans objects with Method "Genefinder"
  $command    .= "query find CDS where Method = twinscan AND Species = \"*elegans\"\nkill\n";           # Any elegans objects with Method "twinscan"
  $command    .= "save\nquit\n";

  &DbWrite($command,$tace,$autoacedir,"anon");
  $log->write_to($wormbase->runtime." : Finished.\n\n");
}


################################################
# Remove all trace of tiling array data!!!

sub remove_tiling_data {
  $log->write_to($wormbase->runtime." : Removing tiling array data.\n");
  my $command = "query find Sequence \"*tiling*\"\nkill\n";
  $command .= " query find Homol_data \"*tiling_array*\"\nkill\n";
  $command    .= "save\nquit\n";
  &DbWrite($command,$tace,$autoacedir,"tiling_array_removal_tool");
  $log->write_to($wormbase->runtime." : Finished.\n\n");
}


###################################################
# Parses the lists from the config files     

sub parseconfig {

  $log->write_to( $wormbase->runtime. ": starting parseconfig subroutine\n");
  my ($filename,$dbname);
  open(CONFIG,"$configfile");
  while(<CONFIG>) {
	next if /#/;
	next unless /\w/;
    my %makefile;
    foreach my $pair (split(/\t+/,$_)) {
		my($tag,$value)= ($pair =~ /(\w+)=(.*)/);
		if( $tag and $value) {
	    	$makefile{$tag} = $value;
		}
		else {
	    	$log->log_and_die("Ill formed config line $_ :\n");
	    }
    }
    next if $makefile{'path'}; #database path defn used in make_acefiles.pl
    $dbname = $makefile{'db'};
    $filename = $makefile{'file'};
    # check that file exists before adding to array and is not zero bytes
    if (-e "$wormbasedir"."/$dbname/"."$filename") {
      if (-z "$wormbasedir"."/$dbname/"."$filename") {
	$log->write_to( "ERROR: file $wormbasedir/$dbname/$filename is zero bytes !\n");
      	$log->error;
	$errors++;
      } elsif (-d "$wormbasedir"."/$dbname/"."$filename") {
	$log->write_to( "ERROR: file $wormbasedir/$dbname/$filename is a directory !\n");
      	$log->error;
	$errors++;
      }
      else{
			push (@filenames,"$wormbasedir"."/$dbname/"."$filename");
			$log->write_to( "* Parse config file : file $wormbasedir/$dbname/$filename noted ..\n");
      }
    }
    elsif( $dbname eq 'misc') {
    	push(@filenames,$wormbase->misc_static."/$filename");
    	$log->write_to( "* Parse config file : file ".$wormbase->misc_static."/$filename noted ..\n");
    }
    elsif( $dbname eq 'config') {
    	if(-e "$basedir/autoace_config/$filename"){
    		push(@filenames,"$basedir/autoace_config/$filename");
    	}else{
    		$log->error("ERROR: file $basedir/autoace_config/$filename is not existent !\n");
    	}
	}
    else {
      $log->write_to( "ERROR: file $wormbasedir/$dbname/$filename is not existent !\n");
      $log->error;
      $errors++;
      next;
    }
    
  }
  close(CONFIG);
  $log->write_to( $wormbase->runtime. ": Finished\n\n");
}




###################################################
# Re-initialize the database
# cleans and re-initalizes the ACEDB residing in $dbpath
# then parses .ace files in @filenames

sub reinitdb {

  $log->write_to( $wormbase->runtime. ": Starting reinitdb subroutine\n");

  if( -e "$dbpath/wspec/models.wrm" ) {
    $log->write_to("$dbpath/wspec/model already exists . . \n");
    if (-e "$dbpath/database/lock.wrm") {
      $log->log_and_die( "*Reinitdb error - lock.wrm file present..\n");
    }

    $wormbase->delete_files_from("$dbpath/database",".\.wrm","-");
  }
  else {
    $log->log_and_die("models file missing from $dbpath/wspec\n") unless (-e "$dbpath/wspec/models.wrm");
  }

  #if in debug then need to edit password file to allow non wormpub user.
  if( $wormbase->test) {
    my $user = `whoami`;
    open(PWD,"<$dbpath/wspec/passwd.wrm") or $log->log_and_die("cant edit $dbpath/wspec/passwd.wrm\n");
    undef $/;
    my $pass = <PWD>;
    close PWD;
    $pass =~ s/wormpub/wormpub\n$user/;
    $\ = "\n";
    system("chmod u+w $dbpath/wspec/passwd.wrm");
    open(PWD,">$dbpath/wspec/passwd.wrm") or $log->log_and_die("cant write new $dbpath/wspec/passwd.wrm\n");
    print PWD $pass;
    close PWD;
  }

  my $command = "y\n";
  $log->write_to( $wormbase->runtime. ": reinitializing the database\n");
  &DbWrite($command,$tace,$dbpath,"ReInitDB");


  foreach my $filename (@filenames) {
    if (-e $filename) {
      my $runtime = $wormbase->runtime;
      $log->write_to( "* Reinitdb: started parsing $filename at $runtime\n");
      my ($tsuser) = $filename =~ (/^\S+\/(\S+)\_/);
      $wormbase->load_to_database( $dbpath, $filename, $tsuser, $log );
    } else {
      $log->write_to( "* Reinitdb: $filename is not existent - skipping ..\n");
      next;
    }
  }
  $log->write_to( $wormbase->runtime. ": Finished.\n\n");

}


###################################################
# Alan Coulson maintains a ContigC
# database in ~cemap for the physical map.
# This is dumped in file ~cemap/cen2hs.ace 
# (makecen2hs.pl nightly cron job on rathbin)

sub physical_map_stuff{

  $log->write_to( $wormbase->runtime. ": starting physical_map_stuff subroutine\n");

# This data is permanently in geneace now, the previous file was no longer
# being updated once Alan left
  
  # now make the maps
  my $command = "gif makemaps -all\nsave\ngif makemaps -seqclonemap ".$wormbase->acefiles."/seqclonemap.ace\n";
  $command .= "pparse ".$wormbase->acefiles."/seqclonemap.ace\nsave\nquit\n";
  &DbWrite($command,$giface,$dbpath,"MakeMaps");

  $log->write_to( $wormbase->runtime. ": finished\n\n");
}



#########################################
#  Help and usage
#########################################
sub usage {
  my $error = shift;

  if ($error eq "Help") {
    # Normal help menu
    system ('perldoc',$0);
    exit (0);
  }
}

sub check_make_autoace {
  local (*BUILDLOG);

  $log->write_to( $wormbase->runtime. ": Entering check_make_autoace subroutine\n");

  my $log_file = $log->get_file;

  print "Looking at log file: $log_file\n";  
  print "Open log file $log_file\n";
  
  my ($parsefile,$parsefilename);
  my $builderrors = 0;

  open (BUILDLOG, "<$log_file") || $log->log_and_die("Couldn't open $log_file out\n");
  while (<BUILDLOG>) {
    if (/^\* Reinitdb: started parsing (\S+)/) {
      $parsefile = $1;
    }
    if ((/^\/\/ objects processed: (\d+) found, (\d+) parsed ok, (\d+) parse failed/) && ($parsefile ne "")) {
      my $object_count = $1;
      my $error_count  = $3;
      (printf "%6s parse failures of %6s objects from file: $parsefile\n", $error_count,$object_count);
      if ($error_count > 0) {
	$parsefilename = $parsefile;
	$parsefilename =~ s/$basedir//;
	$log->write_to(sprintf("%6s parse failures of %6s objects from file: $parsefilename\n", $error_count,$object_count));
	$builderrors++;
      }
      ($parsefile,$parsefilename) = "";
    }
  }
  close BUILDLOG;


  # look for objects with no Gene tag
  $log->write_to( "\n". $wormbase->runtime. ": Looking for CDSs, Transcripts, Pseudogenes with no Gene tag\n");
  my $db = Ace->connect(-path=>$autoacedir, -program =>$tace) || $log->log_and_die("Connection failure: ". Ace->error);

  my @genes= $db->fetch(-query=>'find worm_genes NOT Gene');
  if(@genes){
    foreach (@genes){
      $log->write_to( "ERROR: $_ has no Gene tag, please add valid Gene ID from geneace\n");
      $log->error;
      $builderrors++;
    }
  }
  $db->close;

  $log->write_to( $wormbase->runtime. ": Finished subroutine\n\n");

  return ($builderrors);
}

sub allcmid
  {
    # make the allcmid file needed for the farm
    my $command = "query find genome_sequence\nDNA -f ".$wormbase->autoace."/allcmid\nquit\n";
    open (WRITEDB, "| $tace $basedir/autoace ") || $log->log_and_die("Couldn't open pipe to autoace\n");
    print WRITEDB $command;
    close (WRITEDB);
  }

sub mail_reminder 
  {
    my $builder = $wormbase->debug ? $wormbase->debug : "wormbase";
    open (EMAIL,  "|/usr/bin/mailx -s \"WormBase build reminder\" \"$builder\@sanger.ac.uk\" ");
    print EMAIL "Dear builder,\n\n";
    print EMAIL "You have just run autoace_minder.pl -build.  This will probably take 5-6 hours\n";
    print EMAIL "to run.  You should therefore start work on the blast pipeline. So put down that\n";
    print EMAIL "coffee and do some work.\n\n";
    print EMAIL "Yours sincerely,\nOtto\n";
    close (EMAIL);
  }


sub createdirs {

  $log->write_to( $wormbase->runtime. ": starting createdirs subroutine\n");

  my $chromes  = "$dbpath/CHROMOSOMES";
  my $db       = "$dbpath/database";		
  my $new      = "$db/new";
  my $touch    = "$db/touched";
  my $ace      = "$dbpath/acefiles";
  my $rel      = "$dbpath/release";
  my $wspec    = "$dbpath/wspec";
  my @dirarray    = ("$dbpath","$chromes","$db","$new","$touch","$ace","$rel","$wspec");
  
  foreach (@dirarray) {	
    my $present_dir = $_;
    if (-d $present_dir) {
      $log->write_to( "\t** $present_dir - already present\n");
      print "** Skipping $present_dir - already present\n";
    } else {
      $log->write_to("making $present_dir\n");
      mkpath($present_dir);
    }

  }

}


__END__

=pod

=head1 NAME - make_autoace.pl

=head2 USAGE

make_autoace.pl  makes the autoace database in a given directory.

make_autoace.pl  arguments:

=over 4

=item *

-database path_of_database => location of the new autoace directory

=item *

-buildautoace => rebuild the database from source databases (geneace, camace etc)

=item *

-buildrelease => creates only the distribution (release) files

=item *

-test => runs in test mode and uses test environment in ~wormpub/TEST_BUILD
=back
 

=cut
















