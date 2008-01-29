# Wormbase.pm - module for general use by many Wormbase scripts
# adapted from babel.pl
# put together by krb, but mostly using stuff in babel.pl which
# was done by dl1 et al.
# SPECIES BRANCH

package Wormbase;
use strict;
# use lib $ENV{'CVS_DIR'};
use Carp;
use Ace;
use Log_files;
use File::Path;
use File::stat;
use Storable;
use Species;

our @core_organisms=qw(Elegans Briggsae Remanei Brenneri Japonica Heterorhabditis Pristionchus);
our @tier3_organisms=qw(Brugia);
our @allowed_organisms=(@core_organisms, @tier3_organisms); #class data

sub initialize {
  my $class = shift;
  my %params = @_;
  my $self = {};
  bless $self , $class;

  # populate passed parameters ( will overwrite defaults if set )
  foreach ( keys %params ) {
    my $key = $_;
    $key =~ s/-//;
    $self->{$key} = $params{$_};
  }
  $self->{'version'} = 666 if( $self->test);
  print STDERR "Using ".$self->{'autoace'}."\n" if( $self->{'autoace'} );
  #$self->establish_paths;
  return $self;
}

#################################################################################

# DEMO constructor
#
# should become: initialize(-organism => Elegans,......) 
sub new {
  my $class = shift;
  my %params=@_;

  my $self;
  my $ORGANISM=($params{'-organism'}||'Elegans'); # fixed at the moment
  $ORGANISM = "\u$ORGANISM";	#make sure 1st letter caps
  die "invalid organism: $ORGANISM" if ! grep {$_ eq $ORGANISM} @allowed_organisms;

  $params{'-species'} = lc $ORGANISM;
  $self=$ORGANISM->_new(\%params);
  $self->establish_paths;
  return $self;
}

#######################################################################

sub get_wormbase_version {
  my $self = shift;
  unless ( $self->{'version'} ) {
    my $dir = $self->autoace;
    if ( -e ("$dir/wspec/database.wrm") ) {
      my $WS_version = `grep "NAME WS" $dir/wspec/database.wrm`;
      chomp($WS_version);
      $WS_version =~ s/.*WS//;
      $self->version($WS_version);
    } else {
      $self->version(666);
    }
  }

  return ( $self->{'version'} );
}

###################################################################################

sub get_wormbase_version_name 
  {
    my $self = shift;
    my $version = $self->get_wormbase_version;
    return("WS$version");
  }

sub get_dev_version {
  my $self = shift;
  unless ( $self->{'version'} ) {
    my $dir = $self->database('current');
    if ( -e ("$dir/wspec/database.wrm") ) {
      my $WS_version = `grep "NAME WS" $dir/wspec/database.wrm`;
      chomp($WS_version);
      $WS_version =~ s/.*WS//;
      $self->version($WS_version);
    } else {
      $self->version(666);
    }
  }

  return ( $self->{'version'} );
}
###################################################################################

sub version {
  my $self = shift;
  my $ver  = shift;
  $self->{'version'} = $ver if $ver;
  return $self->{'version'};
}

sub get_wormbase_release_date {

  my $self   = shift;
  my $format = shift;

  if (!(defined($format))) {
    $format = "long";
  } elsif ($format eq "short") {
    $format = "short";
  } elsif ($format eq "both") {
    $format = "both";
  } else {
    $format = "long";
  }

  
  my $line = `ls -l /nfs/disk69/ftp/pub/wormbase/development_release/md5sum.WS*`;
  my @split = split(/\s+/,$line);

  my $month = $split[5];
  my $month2;

  if ($month eq "Jan") {
    $month = "January";   $month2 = "01";
  } elsif ($month eq "Feb") {
    $month = "February";  $month2 = "02";
  } elsif ($month eq "Mar") {
    $month = "March";     $month2 = "03";
  } elsif ($month eq "Apr") {
    $month = "April";     $month2 = "04";
  } elsif ($month eq "May") {
    $month = "May";       $month2 = "05";
  } elsif ($month eq "Jun") {
    $month = "June";      $month2 = "06";
  } elsif ($month eq "Jul") {
    $month = "July";      $month2 = "07";
  } elsif ($month eq "Aug") {
    $month = "August";    $month2 = "08";
  } elsif ($month eq "Sep") {
    $month = "September"; $month2 = "09";
  } elsif ($month eq "Oct") {
    $month = "October";   $month2 = "10";
  } elsif ($month eq "Nov") {
    $month = "November";  $month2 = "11";
  } elsif ($month eq "Dec") {
    $month = "December";  $month2 = "12";
  }

  my $day = $split[6];

  my $day2;
  if (length($day) == 1) {
    $day2 = "0".$day;
  } else {
    $day2 = $day;
  }

  if ($day eq "1") {
    $day .= "st";
  } elsif ($day eq "2") {
    $day .= "nd";
  } elsif ($day eq "3") {
    $day .= "rd";
  } elsif ($day eq "21") {
    $day .= "st";
  } elsif ($day eq "22") {
    $day .= "nd";
  } elsif ($day eq "23") {
    $day .= "rd";
  } elsif ($day eq "31") {
    $day .= "st";
  } else {
    $day .= "th";
  }

  my $year = `date`;
  $year = substr($year,-3,2);

  # make a text style date
  my $date = $day." ".$month;

  # make a regular xx/xx/xx date
  my $date2 = $day2."/".$month2."/".$year;

  return($date)        if ($format eq "long");
  return($date2)       if ($format eq "short");
  return($date2,$date) if ($format eq "both"); 
}

###################################################################################

sub FetchData {
  my $self = shift;
  my ( $file, $ref, $dir ) = @_;

  # directory to load from can be passed in so that /acari can load files copied over
  unless ($dir) {
    $dir = $self->common_data;
  }
  print STDERR "using $dir for COMMON_DATA\n";
  open( FH, "<$dir/$file.dat" ) or die "can't open $dir/$file.dat\t:$!";
  undef $/;
  my $VAR1;
  my $data = <FH>;
  eval $data;
  die if $@;
  $/ = "\n";
  close FH;
  my $keycount = scalar keys %$VAR1;
  die "$file retrieval through FetchData failed - dat file is empty\n" if $keycount == 0;
  %$ref = (%$VAR1);
}

###################################################################################

sub get_script_version {
  my $self = shift;
  my $script = shift;
  my $script_dir = $ENV{'CVS_DIR'};
  my $version;
  open (GET_SCRIPT_LIST, "/bin/ls -l $script_dir/$script |");
  while (<GET_SCRIPT_LIST>) {
    chomp;
    my $stringlen = length ($_);
    $version = substr ($_,$stringlen-3,3);
    last;
  }
  close GET_SCRIPT_LIST;
  return ($version);
} 


#################################################################################

sub copy_check {
  my $self = shift;
  my ($file1,$file2) = @_;
  my $match = "";
  my $O_SIZE = (-s $file1);
  my $N_SIZE = (-s $file2);
  
  return 0 unless ($O_SIZE && $N_SIZE);

  if ($O_SIZE != $N_SIZE) {
    $match = 0;
  } else {
    $match = 1;
  }
  return ($match);
} 


#################################################################################

sub mail_maintainer {
  my $self = shift;
  my ( $name, $maintainer, $logfile ) = @_;
  $maintainer = "ar2\@sanger.ac.uk, pad\@sanger.ac.uk, mt3\@sanger.ac.uk, gw3\@sanger.ac.uk, mh6\@sanger.ac.uk"    if ( $maintainer =~ m/All/i );
  croak "trying to email a log to a file - this will overwrite the existing file -STOPPING\nAre you passing a file name to Log object? \n"  if ( -e $maintainer );
  open( OUTLOG, "|mailx -s \"$name\" $maintainer " );
  if ($logfile) {
    open( READLOG, "<$logfile" );
    while (<READLOG>) {
      print OUTLOG "$_";
    }
    close READLOG;
  } else {
    print OUTLOG "$name";
  }
  close OUTLOG or die "didn't close mail properly\n\n";
  return;
}


#################################################################################

sub DNA_string_reverse {
  my $self = shift;
  my $revseq = reverse shift;
  $revseq =~ tr/a/x/;
  $revseq =~ tr/t/a/;
  $revseq =~ tr/x/t/;
  $revseq =~ tr/g/x/;
  $revseq =~ tr/c/g/;
  $revseq =~ tr/x/c/;
  return ($revseq);
}

#################################################################################

sub DNA_string_composition {
  my $self = shift;
  my $seq  = shift;
  $seq =~ tr/[A-Z]/[a-z]/;
  my $A = $seq =~ tr/a/a/;
  my $C = $seq =~ tr/c/c/;
  my $G = $seq =~ tr/g/g/;
  my $T = $seq =~ tr/t/t/;
  my $N = $seq =~ tr/n/n/;
  my $P = $seq =~ tr/-/-/;
  return ( $A, $C, $G, $T, $N, $P );
}

#################################################################################

sub gff_sort {
  my $self = shift;
  my(@a, @n, @s, @e, @f);
  while (<>) {
    s/#.*//;
    next unless /\S/;
    @f = split /\t/;
    push @a, $_;
    push @n, $f[0];
    push @s, $f[3];
    push @e, $f[4];
  }

  foreach my $i ( sort { $n[$a] cmp $n[$b] or $s[$a] <=> $s[$b] or $e[$a] <=> $e[$b] } 0 .. $#a ) {
    print $a[$i];
  }
}

#################################################################################

#################################################################################

#  Subroutines for generating release letter

##################################################################################
# Databases used in build                                                        #
##################################################################################

sub release_databases
  {
    my $self = shift;
    #GET THE DATABASES USED IN THIS BUILD

    #get the non_cambridge DB info from file
    open( DBS, $self->basedir."/Primary_databases_used_in_build" );
    my ( $stlace, $citace, $brigdb, $cshace );
    my %dates;
    while (<DBS>) {
      chomp;
      my @info = split(/ : /,$_);
      $dates{$info[0]} = $info[1];
    }
    foreach my $key ( keys %dates) {
      my $oldstyle = $dates{$key};
      my $newstyle = "20".substr($oldstyle,0,2)."-".substr($oldstyle,2,2)."-".substr($oldstyle,4);
      $dates{$key} = $newstyle;
    }


    #get the Cambridge dates directly from block file 1
    my @date = $self->find_file_last_modified($self->database("camace")."/database/block1.wrm");
    $dates{camace} = $date[0];
    @date = $self->find_file_last_modified($self->database("geneace")."/database/block1.wrm");
    $dates{genace} = $date[0];

    #PARSE THE RELEASE LETTER FOR LAST BUILD INFO
    my $old_ver = $self->get_wormbase_version - 1;
    my $ver     = $old_ver + 1;

    my %old_dates;
    my $located = 0;
    my $count   = 0;		#determines how many lines to read = no databases
    open( OLD_LETTER, $self->reports."letter.WS$old_ver" );
    while (<OLD_LETTER>) {
      if ( ( $located == 1 ) && ( $count <= 6 ) ) {
	chomp;
	my @info = split( / : | - / , $_ );

	#this will put some crap in the hash from the 1st two line of the section but it no matter
	$old_dates{ $info[0] } = $info[1];
	$count++;
      } elsif ( $_ =~ m/Primary/ ) {
	$located = 1;
      }
    }
    my $dbaseFile = $self->reports."/dbases";
    open( WRITE, ">$dbaseFile" );

    print WRITE "Primary databases used in build WS$ver\n------------------------------------\n";
    foreach my $key ( sort keys %dates ) {
      print WRITE "$key : $dates{$key}";
      if ( "$dates{$key}" gt "$old_dates{$key}" ) {
	print WRITE " - updated\n";
      } elsif ( "$dates{$key}" lt "$old_dates{$key}" ) {
	print WRITE "you're using a older version of $key than for WS$old_ver ! ! \n";
      } else {
	print WRITE "\n";
      }
    }
    close WRITE;

    my $name       = "Database update report";
    my $maintainer = "All";
    $self->mail_maintainer( $name, $maintainer, $dbaseFile );

    return 1;
  }

##################################################################################
# Returns the date yyyy-mm-dd and time hh:mm:ss file was last modified           #
##################################################################################
sub find_file_last_modified {
  my $self     = shift;
  my $filename = shift;
  open( FILE, "<$filename" ) || die "cant open file $filename\n";
  my @fileinfo = stat $filename;
  my @date     = localtime( $fileinfo[9] );
  close(FILE);
  my $year = sprintf( "%d-%02d-%02d\n", $date[5] + 1900, $date[4] + 1, $date[3] );
  my $time = "$date[2]:$date[1]:$date[0]";
  chomp $year;

  my @last_modified = ( $year, $time );
  return @last_modified;
}

##################################################################################
# DNA Sequence composition                                                       #
##################################################################################

sub release_composition
  {
    my $self = shift;
    my $log = shift;
    #get the old info from current_DB
    my $ver     = $self->get_wormbase_version;
    my $old_ver = $ver - 1;
    my %old_data;
    $old_data{"-"} = 0;		# initialise to avoid problems later if no gaps
    my $old_letter = $self->database("WS$old_ver")."/CHROMOSOMES/composition.all";
    open (OLD, "<$old_letter") or $log->log_and_die("cant open data file - $old_letter");
    while (<OLD>) {
      chomp;
      if ( $_ =~ m/(\d+)\s+total$/ ) {

	#my $tot = $1;$tot =~ s/,//g; # get rid of commas
	$old_data{Total} = $1;
      } elsif ( $_ =~ m/^\s+([\w-]{1})\s+(\d+)/ ) {
	$old_data{"$1"} = $2;
      }
    }
    close(OLD);

    #now get the new stuff to compare
    my $new_letter = $self->chromosomes . "/composition.all";
    my %new_data;

    $new_data{"-"} = 0;		# initialise to avoid problems later if no gaps
    open( NEW, "<$new_letter" ) || die "cant open data file - $new_letter";
    while (<NEW>) {
      chomp;
      if ( $_ =~ m/(\d+)\s+total$/ ) {
	$new_data{Total} = $1;
      } elsif ( $_ =~ m/^\s+([\w-]{1})\s+(\d+)/ ) {
	$new_data{"$1"} = $2;
      }
    }
    close NEW;

    # Now check the differences
    my %change_data;
    my $compositionFile = $self->autoace . "/REPORTS/composition";
    open( COMP_ANALYSIS, ">$compositionFile" ) || die "cant open $compositionFile";
    print COMP_ANALYSIS "Genome sequence composition:\n----------------------------\n\n";
    print COMP_ANALYSIS "       \tWS$ver       \tWS$old_ver      \tchange\n";
    print COMP_ANALYSIS "----------------------------------------------\n";
    foreach my $key ( keys %old_data ) {
      $change_data{$key} = $new_data{$key} - $old_data{$key};
    }

    my @order = ( "a", "c", "g", "t", "n", "-", "Total" ); # gaps removed
    foreach (@order) {
      if ( "$_" eq "Total" ) {
	print COMP_ANALYSIS "\n";
      }
      if (! exists $old_data{$_}) {print "no data for $_\n"; next}
      printf COMP_ANALYSIS ( "%-5s\t%-8d\t%-8d\t%+4d\n", $_, $new_data{$_}, $old_data{$_}, $change_data{$_} );
    }

    # Report file/email

    my $name       = "BUILD REPORT: Sequence composition";
    my $maintainer = "All";

    if ( $change_data{"-"} > 0 ) {
      print COMP_ANALYSIS "Number of gaps has increased - please investigate ! \n";
      $name = $name . " : Introduced a gap";

    }
    if ( $change_data{"Total"} < 0 ) {

      print COMP_ANALYSIS "Total number of bases has decreased - please investigate ! \n";
      $name = $name . " : Lost sequence";
    }
    if ( $change_data{"Total"} > 0 ) {
      print COMP_ANALYSIS "Total number of bases has increased - please investigate ! \n";
      $name = $name . " : Gained sequence";
    }
    close COMP_ANALYSIS;

    $self->mail_maintainer( $name, $maintainer, $compositionFile );

    return 1;
  }

##################################################################################
#  Wormpep                                                                       #
##################################################################################

sub release_wormpep		#($number_cds $number_total $number_alternate )
  {  
    my $self = shift;
    my ($number_cds, $number_total, $number_alternate) = @_;
    my $ver = $self->get_wormbase_version;
    my $old_ver = $ver -1;

    #extract data from new wormpep files
    my $wormpep = $self->wormpep;
    my $lost     = `more $wormpep/wormpep.diff$ver | grep 'lost' | wc -l`;
    my $new      = `more $wormpep/wormpep.diff$ver | grep 'new' | wc -l`;
    my $changed  = `more $wormpep/wormpep.diff$ver | grep 'changed' | wc -l`;
    my $appeared = `more $wormpep/wormpep.diff$ver | grep 'appear' | wc -l`;
    my $entries  = `cat $wormpep/wormpep.diff$ver | wc -l`;
    my $net      = $new + $appeared - $lost;
    my $codingDNA;

    #get no of coding bases from log file
    open( THIS_LOG, "$wormpep/wormpep_current.log" );
    while (<THIS_LOG>) {
      if ( $_ =~ /No\. of sequences \(letters\) written:\s+\d+\,\d+\s+\((.*)\)/ ) {
	$codingDNA = $1;
      }
    }

    #write new letter
    my $wormpepFile = $self->reports."/wormpep";
    open( LETTER, ">$wormpepFile" ) || die "cant open $wormpepFile\n";

    print LETTER "\n\nWormpep data set:\n----------------------------\n";
    print LETTER
      "\nThere are $number_cds CDS in autoace, $number_total when counting $number_alternate alternate splice forms.\n
The $number_total sequences contain $codingDNA base pairs in total.\n\n";

    print LETTER "Modified entries      $changed";
    print LETTER "Deleted entries       $lost";
    print LETTER "New entries           $new";
    print LETTER "Reappeared entries    $appeared\n";
    printf LETTER "Net change  %+d", $net;

    #get the number of CDS's in the previous build
    open( OLD_LOG, $self->basedir."/WORMPEP/wormpep$old_ver/wormpep_current.log" );
    my $oldCDS;
    while (<OLD_LOG>) {
      if ( $_ =~ /No\. of sequences \(letters\) written:\s+(\d+\,\d+)\s+\(.*\)/ ) {
	$oldCDS = $1;
	$oldCDS =~ s/,//g;
      }
    }
    close OLD_LOG;

    #check
    my $mail;
    if ( $lost + $new + $changed + $appeared != $entries ) {
      print LETTER "cat of wormpep.diff$ver does not add up to the changes (from $0)";
    }
    if ( $oldCDS + $net != $number_total ) {
      print LETTER
	"\nThe differnce between the total CDS's of this ($number_total) and the last build ($oldCDS) does not equal the net change $net\nPlease investigate! ! \n";
    }

    close LETTER;

    my $name       = "Wormpep release stats";
    my $maintainer = $self->debug ? $self->debug : "All";
    $self->mail_maintainer( $name, $maintainer, $wormpepFile );

    return 1;
  }

#end of release letter generating subs
#############################################

sub test_user_wormpub {
  my $self = shift;
  my $name = `whoami`;
  chomp $name;
  if ( "$name" eq "wormpub" ) {
    print "running scripts as user wormpub . . . \n\n";
    return 1;
  }
  elsif ($name eq "wormpipe") {
    return 1;
  }
  elsif ($self->test) {
    print "running in Test\n";
    return 1;
  }
  else {
    print "You are doing this as $name NOT wormpub ! \n\n If you are going to alter autoace in any way it will break.\nDo you want to continue? (y/n). . ";
    my $response = <STDIN>;
    chomp $response;
    if ( "$response" eq "n" ) {
      die "probably for the best !\n";
    }
    else {
      print
	"OK - on your head be it !\nBack to the script . .\n#########################################################\n\n\n";
      return 0;
    }
  }
 }
#############################################
sub runtime {
  my $self    = shift;
  my $runtime = `date +%H:%M:%S`;
  chomp $runtime;
  return $runtime;
}
###############################################
sub rundate {
  my $self    = shift;
  my $rundate = `date +%y%m%d`;
  chomp $rundate;
  return $rundate;
}

###################################################
# subs to get the correct version of ACEDB binaries
sub tace {
  my $self = shift;
  return $self->{'tace'};
}

sub giface {
  my $self = shift;
  return $self->{'giface'};
}

####################################
# Check for database write access
####################################

sub check_write_access {

  my $self         = shift;
  my $database     = shift;
  my $write_access = "yes";

  $write_access = "no" if ( -e "${database}/database/lock.wrm" );
  return ($write_access);

}

####################################
# Delete files from directory
####################################
sub delete_files_from {
  my $self = shift;
  my ( $directory, $pattern, $folder ) = @_;
  my $file;
  my $delete_count = 0;
  my $fail_warn    = 1;

  return undef unless ( -e $directory );

  if ( $folder eq "+" ) {
    print "Removing entire dir and subdirs of $directory\n";
    $delete_count = rmtree($directory);
  } else {
    opendir( TO_GO, $directory ) or die "cant get listing of $directory:\t$!\n";

    #   $pattern = "." if $pattern eq "*";

    $pattern = "." unless $pattern;
    $pattern =~ s/\*/\./g;

    while ( $file = readdir(TO_GO) ) {
      next if ( $file eq "." or $file eq ".." );
      if ( $file =~ /$pattern/ ) {
	if ( unlink("$directory/$file") ) {
	  $delete_count++;
	} else {
	  warn "couldn't unlink $directory/$file :\t$!\n";
	  undef $fail_warn;
	}
      }
    }
  }
  return $fail_warn ? $delete_count : $fail_warn; # undef if failed else no. files removed;
}

####################################
# do various checks on the files output from a script
# (or part of a script) - the tests are read from the config file
# ~wormpub/BUILD/autoace_config/autoace.config
####################################

sub check_files {
  my ($self, $log, $part) = @_;

  # read the filenames and criteria from the config file
  my $config = $self->basedir . "/autoace_config/check_file.config";
  open(FCCONFIG, "<$config") || $log->log_and_die("Can't open $config\n");

  my $species = $self->species;
  my %criteria;
  my $found_species = '';
  my $found_script = 0;
  my $found_a_file = 0;
  my $file;

  my $script_name = $0;
  $script_name =~ s/.+\/(\S+)/$1/; # remove header of path

  while (my $line = <FCCONFIG>) {
    chomp $line;
    if ($line =~ /^#/ || $line =~ /^\s+$/) {  
      next;
    } elsif ($line =~ /^SPECIES/) {
      $found_species = '';
      $found_script = 0;
      if ($line =~ /^SPECIES\s+$species/) {
	$found_species = 'species';
      }
      if ($line =~ /^SPECIES\s+default/) {
	$found_species = 'default';
      }
    } elsif ($found_script && $line !~ /^SCRIPT/) {
      if ($line =~ /^\s*FILE/) {
	($file) = $line =~ /^\s*FILE\s+(\S+)/;
	$file =~ s/wormbase->/self->/; # convert filenames with '$wormbase->' in to '$self->'
	if ($file =~ /(\$\S+\-\>[\w_\(\)\']+)(\/\S+)/) {
	  $file = eval($1) . $2;         # and expand to the full path
	}
	# don't want to do a default test it we already have the tests
	# that are specific for this species
	if ($found_species eq 'default' &&
	    exists $criteria{$file}) {next;}
	$found_a_file = 1;
	$criteria{$file}{exists} = 1;
      } elsif ($line =~ /^\s+(\S+)\s+(\S+)/) {
	my $key = $1;
	my $value = $2;
	# get and store the tests for this file
	if ($key eq 'lines' || $key eq 'requires') {
	  push @{$criteria{$file}{$key}}, $value;
	} else {
	  $criteria{$file}{$key} = $value;
	}
      }
    } elsif ($found_species) {
      if ($line =~ /^SCRIPT/) {
	$found_script = 0;
	if ($line =~ /^SCRIPT\s+$script_name\s*$/ || 
	    (defined $part && $line =~ /^SCRIPT\s+$script_name\s+$part$/)) {
	  $found_script = 1;
	}
      }
    }
  }
  close(FCCONFIG);

  # complain if we didn't find an entry for this script
  if (!$found_a_file) {
    if ( $log) {
      $log->write_to("WARNING: Couldn't find any files to test in $config\n");
    }
    carp "WARNING: Couldn''t find any files to test in $config\n";
    return 1;
  }

  my $errors = 0;
  foreach my $file (keys %criteria) {
    $errors++ if ($self->check_file($file, $log, %{$criteria{$file}}));
  }
  
  return $errors;		# number of files failing tests
}

####################################

sub check_file {

  my ($self, $file, $log, %criteria) = @_;

  unless ( -e $file) {
    if ( $log) {
      $log->error;
      $log->write_to("ERROR: Couldn't find file named: $file\n");
    }
    carp "ERROR: Couldn't find file named: $file\n";
    return 1;
  }
  delete $criteria{exists};

  my @problems;

  if (!-r $file) {
    push @problems,  "file is not readable";
  }

  if (!exists $criteria{readonly}) {
    if (!-w $file) {
      push @problems,  "file is not writeable";
    }
  } else {
    delete $criteria{readonly};
  }

  my $size;
  my $second_file_size;
  if (exists $criteria{samesize}) {
    $size = (-s $file) unless $size;
    $second_file_size = (-s $criteria{samesize});
    if ($second_file_size != $size) {
      push @problems,  "file size ($size) not equal to that of file '$criteria{samesize}' ($second_file_size)";
    }
    delete $criteria{samesize};
  }
  if (exists $criteria{similarsize}) {
    $size = (-s $file);
    $second_file_size = (-s $criteria{similarsize});
    if ($second_file_size < $size * 0.9 || $second_file_size > $size * 1.1) {
      push @problems,  "file size ($size) not similar to that of file '$criteria{similarsize}' ($second_file_size)";
    }
    delete $criteria{similarsize};
  }
  if (exists $criteria{minsize}) {
    $size = (-s $file) unless $size;
    if ($size < $criteria{minsize}) {
      push @problems,  "file size ($size) less than required minimum ($criteria{minsize})";
    }
    delete $criteria{minsize};
  }
  if (exists $criteria{maxsize}) {
    $size = (-s $file) unless $size;
    if ($size > $criteria{maxsize}) {
      push @problems, "file size ($size) greater than required maximum ($criteria{maxsize})";
    }
    delete $criteria{maxsize};
  }
  my $lines;
  my $second_file_lines;
  if (exists $criteria{samelines}) {
    ($lines) = (`wc -l $file` =~ /(\d+)/);
    ($second_file_lines) = (`wc -l $criteria{samelines}` =~ /(\d+)/);
    if ($second_file_lines != $lines) {
      push @problems,  "number of lines ($lines) not equal to that of file '$criteria{samelines}' ($second_file_lines)";
    }
    delete $criteria{samelines};
  }
  if (exists $criteria{similarlines}) {
    ($lines) = (`wc -l $file` =~ /(\d+)/) unless $lines;
    ($second_file_lines) = (`wc -l $criteria{similarlines}` =~ /(\d+)/) unless $lines;
    if ($second_file_lines < $lines * 0.9 || $second_file_lines > $lines * 1.1) {
      push @problems,  "number of lines ($lines) not similar to that of file '$criteria{similarlines}' ($second_file_lines)";
    }
    delete $criteria{similarlines};
  }
  if (exists $criteria{minlines}) {
    ($lines) = (`wc -l $file` =~ /(\d+)/) unless $lines;
    if ($lines < $criteria{minlines}) {
      push @problems, "number of lines ($lines) less than required minimum ($criteria{minlines})";
    }
    delete $criteria{minlines};
  }
  if (exists $criteria{maxlines}) {
    ($lines) = (`wc -l $file` =~ /(\d+)/) unless $lines;
    if ($lines > $criteria{maxlines}) {
      push @problems, "number of lines ($lines) greater than required maximum ($criteria{maxlines})";
    }
    delete $criteria{maxlines};
  }
  
  if (exists $criteria{requires} || exists $criteria{line1} || exists $criteria{line2} || exists $criteria{lines}) {
    open (CHECK_FILE, "< $file") || die "Can't open $file\n";
    my $line_count = 0;
    while ($line_count++, my $line = <CHECK_FILE>) {

      if (exists $criteria{requires}) {
	my $re_count = 0;
	foreach my $regex (@{$criteria{requires}}) { # we need to find at least one of each of these regexps in the file
	  if ($line =~ /$regex/) {
	    splice @{$criteria{requires}}, $re_count, 1; # remove the successful regexp frmo the array
	  }
	  $re_count++;
	}
	if (@{$criteria{requires}} == 0 && !(exists $criteria{line1} || exists $criteria{line2} || exists $criteria{lines})) {last;}
      }

      if ($line_count == 1 && exists $criteria{line1}) {
	if ($line !~ /$criteria{line1}/) {
	  push @problems, "line $line_count:\n$line\ndoesn't match criterion 'line1 => /$criteria{line1}/'";
	  last;
	}
	next;			# don't do 'lines' check on line 1 if 'line1' check exists
      }
      if ($line_count == 2 && exists $criteria{line2}) {
	if ($line !~ /$criteria{line2}/) {
	  push @problems, "line $line_count:\n$line\ndoesn't match criterion 'line2 => /$criteria{line2}/'";
	  last;
	}
	next;			# don't do 'lines' check on line 2 if 'line2' check exists
      }
      if ($line_count > 2 && !exists $criteria{lines} && !@{$criteria{requires}}) {last;}
      if (exists $criteria{lines}) {
	my $line_ok = 0;
	foreach my $regex (@{$criteria{lines}}) { # each line in the file must match one of these regexps
	  if ($line =~ /$regex/) {
	    $line_ok = 1;
	    last;
	  }
	}
	if (!$line_ok) {
	  my $regexp = '/'.join('/ /',@{$criteria{lines}}).'/'; # for easier readability
	  push @problems, "line $line_count:\n$line\ndoesn't match criterion 'lines => [$regexp]]'";
	  last;
	}
      }
    }
    close (CHECK_FILE);

    # check if there are any 'requires' regexps which didn't match
    if (exists $criteria{requires} && @{$criteria{requires}}) {
      push @problems, "the criterion 'requires => [@{$criteria{requires}}]' did not match any line";
    }

    delete $criteria{requires};
    delete $criteria{line1};
    delete $criteria{line2};
    delete $criteria{lines};
  }
  if (exists $criteria{gff}) {
    my ($sequence_name, $sequence_start, $sequence_end);
    my $MAX_FEATURE_LENGTH = 100000;
    open (CHECK_FILE, "< $file") || die "Can't open $file\n";
    my $line_count = 0;
    while ($line_count++, my $line = <CHECK_FILE>) {
      ##sequence-region CHROMOSOME_X 1 17718851
      if ($line =~ /^\#\#sequence-region\s+(\S+)\s+(\d+)\s+(\d+)/) {
	($sequence_name, $sequence_start, $sequence_end) = ($1, $2, $3);
	next;
      }
      #CHROMOSOME_X    Link    region  1       17718851        .       +       .       Sequence "CHROMOSOME_X"
      if (defined $sequence_name && $line =~ /^${sequence_name}\s+Link\s+region\s+(\d+)\s+(\d+)/) {
	next;
      }

      if ($line =~ /^\#/) {next;}

      if (my ($gff_source, $gff_start, $gff_end) = ($line =~ /^\S+\s+(\S+)\s+\S+\s+(\d+)\s+(\d+)\s+\S+\s+[-+\.]\s+[012\.]/)) {
	if ($gff_end < $gff_start) {
	  push @problems, "line $line_count:\n$line\nGFF feature start is before the feature end";
	  last;
	}
	# there are 'Genomic_canonical' features longer than 100 Kb
	# there are 'BLAT_NEMATODE' features longer than 100 Kb
	# there are 'Vancouver_fosmid' features longer than 100 Kb
	# F47F6.1c.1 is 107835 bases
	# WBGene00018572 is 107835 bases 
	# Locus lin-42 is 107835 bases
	# Oligo_set Aff_Y116F11.ZZ33 is 105 Kb
	# F16H9.2 is 102695 bases
	# WBGene00008901 is 102695 bases
	my $feature_length = $gff_end - $gff_start;
	if ($feature_length > $MAX_FEATURE_LENGTH && 
	    $gff_source ne 'Genomic_canonical' &&
	    $gff_source ne 'BLAT_NEMATODE' &&
	    $gff_source ne 'Vancouver_fosmid' &&
	    !($line =~ /F47F6.1c.1/) &&
	    !($line =~ /WBGene00018572/) &&
	    !($line =~ /Locus\s+lin-42/) &&
	    !($line =~ /Aff_Y116F11.ZZ33/) &&
	    !($line =~ /F16H9.2/) &&
	    !($line =~ /WBGene00008901/) 
	    ) { 
	  push @problems, "line $line_count:\n$line\nGFF feature is longer than $MAX_FEATURE_LENGTH bases ($feature_length bases)";
# report all length errors
#	  last;
	}
	if (defined $sequence_end && $gff_end > $sequence_end) {
	  push @problems, "line $line_count:\n$line\nfeature is off the end of the sequence";
	  last;
	}
	if ((defined $sequence_start && $gff_start < $sequence_start) || $gff_start < 1) {
	  push @problems, "line $line_count:\n$line\nfeature is before the start of the sequence";
	  last;
	}
      } else {
	push @problems, "line $line_count:\n$line\nis a malformed GFF line";
	last;
      }
    }
    close (CHECK_FILE);
    delete $criteria{gff};
  }
  


  foreach my $c (keys %criteria) {
    push @problems, "unknown criterion in check_file() '$c=>$criteria{$c}'";
  }

  foreach my $problem (@problems) {
      if ($log) {
	$log->error;
	$log->write_to("ERROR: $problem found when checking file '$file'\n");
      }
      carp "ERROR: $problem found when checking file '$file'\n";
  }

  if (!@problems) {$log->write_to("Check file: '$file' OK\n");}
  return @problems;
}



####################################



sub load_to_database {

  my $self     = shift;
  my $database = shift;
  my $file     = shift;
  my $tsuser   = shift;
  my $log      = shift;
  my $no_bk    = shift;

  my $error=0;
  my $species = $self->species;
  my $version = $self->get_wormbase_version;
  my $prev_version = $version-1;
  my $pparse_file = $self->build_data . "/COMPARE/pparse_ace.dat"; # file holding pparse details from previous Builds

  unless ( -e "$file" and -e $database) {
    if ( $log) {
      $log->error;
      $log->write_to("Couldn't find file named: $file or database $database\n");
    }
    print STDERR "Couldn't find file named: $file or database $database\n";
    return 1;
  }

  # get the base filename without the path
  my $basename = $file;
  $basename =~ s/.*\///;

  my $st = stat($file);
  if ( $st->size > 50000000 and !defined ($no_bk) ) {
    $log->write_to("backing up block files before loading $file\n") if $log;
    my $db_dir = $database."/database";
    my $tar_file = "backup.".time.".tgz";
    my $tar_cmd = "tar cvfzP $db_dir/$tar_file $db_dir/block* $db_dir/database.map $db_dir/log.wrm";
    $self->run_command("$tar_cmd", $log);

    # remove old backups keeping the one just made and the previous one.
    my @backups = glob("$db_dir/backup*");
    my %details;
    my @sorted;
    @sorted = sort @backups;
    pop @sorted; pop @sorted;	# remove the newest two
    # . . and delete the rest
    foreach (@sorted) {
      unlink;
    }
  }

  #check whether write access is possible.
  if ( $self->check_write_access($database) eq 'no') {
    print STDERR "cant get write access to $database\n";
    if ($log) {
      $log->log_and_die("cant get write access to $database\n");
    } else {
      die;
    }
  }

  # tsuser is optional but if set, should replace any dots with underscores just in case
  # if not set im using the filename with dots replaced by '_'
  unless ($tsuser) {

    # remove trailing path of filename
    $tsuser = $basename
  }

  $tsuser =~ s/\./_/g;


  my $tace = $self->tace;
  my $command = <<EOF;
pparse $file
save
quit
EOF
  open( WRITEDB, "echo '$command'| $tace -tsuser $tsuser $database |" ) || die "Couldn't open pipe to database\n";

# expect output like:
#
# acedb> // Parsing file /nfs/disk100/wormpub/BUILD/autoace/acefiles/feature_binding_site.ace
# // objects processed: 154 found, 154 parsed ok, 0 parse failed
# // 51 Active Objects
# acedb> // 51 Active Objects
# acedb>
  my $parsed = 0;
  my $active = 0;		# counts of objects

  while (my $line = <WRITEDB>) {
    print "$line";
    if ($line =~ 'ERROR') {
      if ($log) {
	$log->write_to("ERROR while parsing ACE file $file\n$line\n");
	$log->error;
	$error=1;
      }
    } elsif ($line =~ /objects processed:\s+\d+\s+found,\s+(\d+)\s+parsed ok,/) {
      $parsed = $1;
    } elsif ($line =~ /(\d+)\s+Active Objects/) {
      $active = $1;
    }
  }
  close(WRITEDB);

  if (! $error) {
    # check against previous loads of this file
    my $last_parsed;		# objects parsed on the previous build
    my $last_active;
    # get the number of objects in the pparse of this file in the previous Build
    if (open (PPARSE_ACE, "< $pparse_file")) {
      while (my $line = <PPARSE_ACE>) {
	my ($pa_version, $pa_file, $pa_species, $pa_parsed, $pa_active) = split /\s+/, $line;
	if ($pa_version == $prev_version && $pa_file eq $basename && $species eq $pa_species) {
	  # store to get the last one in the previous build
	  $last_parsed = $pa_parsed;
	  $last_active = $pa_active;
	} 
      }
      close (PPARSE_ACE);
    }

    # check the current Build parse object numbers against the previous one
    if (defined $last_parsed) {
      $log->write_to("Version WS$prev_version parsed $last_parsed objects OK with $last_active Active Objects\n");
      $log->write_to("Version WS$version parsed $parsed objects OK with $active Active Objects\n\n");
      if ($parsed < $last_parsed * 0.9 || $parsed > $last_parsed * 1.1
      ||  $active < $last_active * 0.9 || $active > $last_active * 1.1) {
	$log->write_to("*** POSSIBLE ERROR found while parsing ACE file $file\n\n");
	$log->error;
      }
    }

    # now store the details for this pparse
    if (open (PPARSE_ACE, ">> $pparse_file")) {
      print PPARSE_ACE "$version $basename $species $parsed $active\n";
      close (PPARSE_ACE);
    } else {
      $log->write_to("WARNING: Couldn't write to $pparse_file\n\n");
    }
  }
}

####################################
sub wormpep_files {
  my $self = shift;
  return ( "wormpep", "wormpep.accession", "wormpep.dna", "wormpep.history", "wormpep.fasta", "wormpep.table",
	   "wormpep.diff" );
}


sub test        { my $self = shift; return $self->{'test'}; }
sub debug       { my $self = shift; return $self->{'debug'}; }
sub wormpub     { my $self = shift; return $self->{'wormpub'}; }
sub basedir     { my $self = shift; return $self->{'basedir'}; }
sub autoace     { my $self = shift; return $self->{'autoace'}; }
sub wormpep     { my $self = shift; return $self->{'wormpep'}; }
sub peproot     { my $self = shift; return $self->{'peproot'}; }
sub brigpep     { my $self = shift; return $self->{'brigpep'}; }
sub wormrna     { my $self = shift; return $self->{'wormrna'}; }
sub gff         { my $self = shift; return $self->{'gff'}; }
sub gff_splits  { my $self = shift; return $self->{'gff_splits'}; }
sub chromosomes { my $self = shift; return $self->{'chromosomes'}; }
sub logs        { my $self = shift; return $self->{'logs'}; }
sub ftp_upload  { my $self = shift; return $self->{'ftp_upload'}; }
sub ftp_site    { my $self = shift; return $self->{'ftp_site'}; }
sub reports     { my $self = shift; return $self->{'reports'}; }
sub misc_static { my $self = shift; return $self->{'misc_static'}; }
sub misc_dynamic{ my $self = shift; return $self->{'misc_dynamic'}; }
sub primaries   { my $self = shift; return $self->{'primaries'}; }
sub acefiles    { my $self = shift; return $self->{'acefiles'}; }
sub transcripts { my $self = shift; return $self->{'transcripts'}; }
sub blat        { my $self = shift; return $self->{'blat'}; }
sub farm_dump   { my $self = shift; return $self->{'farm_dump'}; }
sub compare     { my $self = shift; return $self->{'compare'}; }
sub checks      { my $self = shift; return $self->{'checks'}; }
sub build_data  { my $self = shift; return $self->{'build_data'}; }
sub ontology    { my $self = shift; return $self->{'ontology'}; }
sub orgdb       { my $self = shift; return $self->{'orgdb'}; }
sub cdna_dir    { my $self = shift; return $self->{'cdna_dir'};}
sub maskedcdna  { my $self = shift; return $self->{'maskedcdna'} ;}
sub genome_seq  { my $self = shift; return $self->autoace."/genome_seq";}


		  # this can be modified by calling script
####################################
sub common_data {
  my $self = shift;
  my $path = shift;
  if ($path) {
    if ( -e $path ) {
      $self->{'common_data'} = $path;
    } else {
      die "$path does not exist\n";
    }
  }
  return $self->{'common_data'};
}

####################################
sub database {
  my $self     = shift;
  my $database = shift;
  if ( $self->{'databases'}->{"$database"} ) {
    return $self->{'databases'}->{"$database"};
  } else {

    # try under the usual database path
    my $poss_path = $self->wormpub . "/DATABASES/$database";
    return $poss_path if ( -e $poss_path );

    #build related database
    $poss_path = $self->basedir . "/$database";
    return $poss_path if ( -e $poss_path );
    print STDERR "no such database $database\n";
    return undef;
  }
}

####################################
sub primary {
  my $self = shift;
  my $database = shift;
  my $path  = $self->{'primary'}->{"$database"};
  print STDERR "no such primary database:$database\n" unless $path&&(-e $path);
  return $path;
}

####################################
# setter methods
sub set_test { 
  my $self = shift; 
  $self->{'test'} = shift; 
  # adjust the paths to point to the TEST_BUILD versions
  $self->establish_paths;
}
sub set_debug { 
  my $self = shift; 
  $self->{'debug'} = shift; 
}

sub establish_paths {
  my $self = shift;

  # Some farm code uses Wormbase.pm subs so to maintain this farm code needs to be OO Wormbase.pm compliant but we dont want 
  # multiple paths of the build (main and farm) reading/writing the same wormbase.store file . Store the farm version in ~wormpipe
  # and might as well use path retrieval routines as with main build.

  if ( $self->{'farm'} ) {
    my $wormpipe= glob("~wormpipe");
    $self->{'autoace'}     = $wormpipe;
    $self->{'acefiles'}    = $self->autoace . "/acefiles";
    $self->{'dump_dir'}    = '/lustre/work1/ensembl/wormpipe/dumps';
    $self->{'orgdb'}       =  $wormpipe;
    $self->{'logs'}        = "$wormpipe/logs";
    $self->{'common_data'} = $self->orgdb . "/COMMON_DATA";
  } else {
    my $basedir;
    ( $self->{'wormpub'} ) = glob("~wormpub");

    # if a specified non-build database is being used

    if ( $self->autoace ) {
      ($basedir) = $self->autoace =~ /(.*)\/\w+$/;
      $self->{'orgdb'} = $self->{'autoace'};
    } else {
      $basedir = $self->wormpub . "/BUILD";
      $basedir = $self->wormpub . "/TEST_BUILD" if $self->test;
      $self->{'autoace'}    = $self->species eq 'elegans' ? "$basedir/autoace" : "$basedir/".$self->species;
      $self->{'orgdb'}      = $self->{'autoace'}; #."/".$self->{'organism'};
    }

    $self->{'basedir'}    = $basedir;
    $self->{'ftp_upload'} = "/nfs/ftp_uploads/wormbase";
    $self->{'ftp_site'}   = "/nfs/disk69/ftp/pub2/wormbase";
    
    #species specific paths
    $self->{'peproot'}    = $basedir . "/WORMPEP";
    $self->{'wormrna'}    = $basedir . "/WORMRNA/wormrna" . $self->get_wormbase_version;
    $self->{'wormpep'}    = $basedir . "/WORMPEP/".$self->pepdir_prefix."pep" . $self->get_wormbase_version;

    $self->{'logs'}        = $self->orgdb . "/logs";
    $self->{'common_data'} = $self->orgdb . "/COMMON_DATA";
    $self->{'chromosomes'} = $self->orgdb . "/CHROMOSOMES";
    $self->{'transcripts'} = $self->orgdb . "/TRANSCRIPTS";
    $self->{'reports'}     = $self->orgdb . "/REPORTS";
    $self->{'acefiles'}    = $self->orgdb . "/acefiles";
    $self->{'gff'}         = $self->chromosomes; #to maintain backwards compatibility 
    $self->{'gff_splits'}  = $self->orgdb . "/GFF_SPLITS";
    $self->{'primaries'}   = $self->basedir . "/PRIMARIES";
    $self->{'blat'}        = $self->orgdb . "/BLAT";
    $self->{'checks'}      = $self->autoace . "/CHECKS";
    $self->{'ontology'}    = $self->autoace . "/ONTOLOGY";
    $self->{'tace'}   = '/software/worm/bin/acedb/tace';
    $self->{'giface'} = '/software/worm/bin/acedb/giface';

    $self->{'databases'}->{'geneace'} = $self->wormpub . "/DATABASES/geneace";
    $self->{'databases'}->{'camace'}  = $self->wormpub . "/DATABASES/camace";
    $self->{'databases'}->{'current'} = $self->wormpub . "/DATABASES/current_DB";
    $self->{'databases'}->{'autoace'} = $self->autoace;

    $self->{'primary'}->{'camace'}  = $self->primaries ."/camace";
    $self->{'primary'}->{'geneace'} = $self->primaries ."/geneace";
    $self->{'primary'}->{'stlace'}  = $self->primaries ."/stlace";
    $self->{'primary'}->{'citace'}  = $self->primaries ."/citace";
    $self->{'primary'}->{'caltech'} = $self->primaries ."/citace"; # to handle the various names used
    $self->{'primary'}->{'csh'}     = $self->primaries ."/cshace";
    $self->{'primary'}->{'cshace'}  = $self->primaries ."/cshace";
    $self->{'primary'}->{'brigace'} = $self->primaries ."/brigace";
    $self->{'primary'}->{'briggsae'}= $self->primaries ."/brigace"; # to handle the various names used

    $self->{'build_data'} = $self->{'basedir'} . "_DATA"; # BUILD_DATA or TEST_BUILD_DATA
    $self->{'misc_static'} = $self->{'build_data'} . "/MISC_STATIC";
    $self->{'misc_dynamic'} = $self->{'build_data'} . "/MISC_DYNAMIC";
    $self->{'compare'}      = $self->{'build_data'} . "/COMPARE";
    $self->{'cdna_dir'}    = $self->{'build_data'} . "/cDNA/".$self->{'species'};
    $self->{'maskedcdna'}  = $basedir . "/cDNA/".$self->{'species'};

    $self->{'farm_dump'}    = '/lustre/work1/ensembl/wormpipe/dumps';

    # create dirs if missing
    mkpath( $self->logs )        unless ( -e $self->logs );
    mkpath( $self->common_data ) unless ( -e $self->common_data );
    mkpath( $self->wormpep )     unless ( -e $self->wormpep );
    mkpath( $self->wormrna )     unless ( -e $self->wormrna ); 
    mkpath( $self->chromosomes ) unless ( -e $self->chromosomes );
    mkpath( $self->transcripts ) unless ( -e $self->transcripts ); 
    mkpath( $self->reports )     unless ( -e $self->reports );
    mkpath( $self->ontology )    unless ( -e $self->ontology );
    mkpath( $self->gff )         unless ( -e $self->gff );
    mkpath( $self->gff_splits )  unless ( -e $self->gff_splits );
    mkpath( $self->primaries )   unless ( -e $self->primaries );
    mkpath( $self->acefiles )    unless ( -e $self->acefiles );
    mkpath( $self->blat )        unless ( -e $self->blat );
    mkpath( $self->checks )      unless ( -e $self->checks );
  }
}

####################################
sub run_script {
  my $self   = shift;
  my $script = shift;
  my $log    = shift;

  my $species = ref $self;
  my $store = $self->autoace . "/$species.store";
  store( $self, $store );
  
  #if user wormpipe this always gives an ERROR and confuses log msgs
  $self->run_command( "chmod -f 775 $store", $log) unless ($self->test_user_wormpub == 1);
  my $command = "perl $ENV{'CVS_DIR'}/$script -store $store";
  print "$command\n" if $self->test;
  return $self->run_command( "$command", $log );
}

####################################
sub bsub_script  {
	my $self   = shift;
  	my $script = shift;
  	my $script_sp = shift; #species that called script is to operate on.
  	my $log    = shift;
  	my $species = ref $self;
  	my $store;
  	my $wbobj;
  	if(lc $species eq lc $script_sp) {  	
		$store = $self->autoace . "/$species.store";
		$wbobj = $self;
	}
	else {
		#create a WormBase Species object to retain test / debug status
		my $wb = Wormbase->new ('-test' => $self->test,
								'-debug' => $self->debug,
								'-organism' => lc($script_sp)
								);
		$store = $wb->autoace . "/". (ref $wb) .".store";
		$wbobj=$wb;
	}
  	
	store($wbobj,$store) unless -e $store;
  	my $command = "bsub $ENV{'CVS_DIR'}/$script -store $store";
  	print "$command\n" if $self->test;
  	return $self->run_command( "$command", $log );
}


####################################
sub run_command {
  my $self    = shift;
  my $command = shift;
  my $log     = shift;
  print STDERR "No log obj passed to run_command by ".(caller)."\n" unless $log;
  $log->write_to("running $command\n") if $log;
  my $return_status = system("$command");
  if ( ( $return_status >> 8 ) != 0 ) {
    if ( $log ) {
      $log->write_to(" WARNING: $command returned non-zero ($return_status)\n");
      $log->error;
    }
    return 1;
  } else {
    $log->write_to("command exited cleanly\n") if $log;
    return 0;
  }
}

####################################
sub wait_for_LSF {
  my $self = shift;
  sleep 10;
  my $jobs = &jobs_left;
  while ( $jobs != 0 ) {
    sleep 100 * $jobs;
    $jobs = &jobs_left;
  }

  print "all jobs finished\n";
  return;

  sub jobs_left {
    my $self  = shift;
    my $count = 0;
    open( JOBS, "bjobs |" );
    while (<JOBS>) {
      print $_;
      next if /JOBID/;		#title line
      $count++;
    }
    close JOBS;
    print "$count jobs left , , \n";
    return $count;
  }
}

####################################
sub checkLSF
  {
    my ($self, $log) = @_;
    unless ( -e "/usr/local/lsf"){
      if ($log) {
	$log->log_and_die("You need to be on cbi1 or other LSF enabled system to run this");
      } else {
	die "You need to be on cbi1 or other LSF enabled system to run this";
      }
    }
  }

####################################
sub table_maker_query {
  my($self, $database, $def) = @_;
  my $fh;
  open( $fh, "echo \"Table-maker -p $def\" | ". $self->tace." $database |" ) || die "Couldn't access $database\n";
  return $fh;
}

####################################
# accessor for the 'core' species
sub species_accessors {
	my $self = shift;
	my %accessors;
	foreach my $species (@core_organisms ){
		next if (lc($species) eq $self->species); #$wormbase already exists for own species.
		my $wb = Wormbase->new( -debug   => $self->debug,
			     -test     => $self->test,
			     -organism => $species
			   );
		$accessors{lc $species} = $wb;
	}
	return %accessors;
}
####################################
# accessor for elegans - required sometime for other species builds
sub build_accessor {
	my $self = shift;
	my $wb = Wormbase->new( -debug   => $self->debug,
			     			-test     => $self->test
			     		);
			     		
	return $wb;
}
####################################
# accessor for the 'tier3' species
sub tier3_species_accessors {
	my $self = shift;
	my %accessors;
	foreach my $species (@tier3_organisms ){
		next if (lc($species) eq $self->species); #$wormbase already exists for own species.
		my $wb = Wormbase->new( -debug   => $self->debug,
			     -test     => $self->test,
			     -organism => $species
			   );
		$accessors{lc $species} = $wb;
	}
	return %accessors;
}

sub species {my $self = shift; return $self->{'species'};}

sub format_sequence
{
	my $self = shift;
	my $seq = shift;
	my $length = shift;
	my $new_seq;
	
	$length = $length ? $length : 60;
	my $left;
	$new_seq = $seq if (length($seq) < $length);
	while ($seq =~ /(\S{$length})/g){
		$new_seq .= $&."\n";
		$left = $';#'
	}
	$new_seq .= $left if ($left);
	return $new_seq;
}

sub get_binned_chroms {
	my $self = shift;	
	my $bin_size = shift;
	$bin_size = 64 unless $bin_size;
	
	my @chroms = $self->get_chromosome_names(-prefix => 1, -mito => 1);
	if (scalar @chroms > 50){
		my @bins;
		my $i=0;
		while ($i<scalar @chroms){
			push (@{$bins[$i % $bin_size]},$chroms[$i]);
			$i++;
		}
		map {$_=join(',',@$_)} @bins;
		@chroms = @bins;
		}
	return \@chroms;
}


################################################################################
#Return a true value
################################################################################

1;

__END__

=pod

=head1 NAME - Wormbase.pm

=head2 DESCRIPTION

The Wormbase.pm module replaces babel.pl which was previouly used
to access some common subroutines for general Wormbase development
work.  

This module provides access to the following subroutines:

=over 4

=item *

get_wormbase_version

This subroutine returns the current WormBase release version.  This is read from
the file: /wormsrv2/autoace/wspec/database.wrm file.  The function returns
the number.

=back

=over 4

=item *

get_wormbase_version_name

As above, but returns the full name, e.g. 'WS47' rather than just '47'

=back

=over 4

=item *

get_wormbase_release_date

Gets the date of the release from the date stamp of the letter.WSxx file in the wormbase ftp 
directory.  Creation of the letter.WSxx file occurs pretty much at the end of the rebuild
so it is really an approximate date.

If no argument is passed to the function it will return the date in 'long' format. E.g.
"21st September".  It will also return this format if the string 'long' is passed to the 
function.

If the string 'short' is passed to the function it will return a six figure date format,
e.g. dd/mm/yy.

If the string 'both' is passed to the function it will return the long and the short versions.

=back


=over 4

=item *

get_wormpep_version

Takes the wormbase version number and adds 10 to it.

=over 4

=item *

get_script_version

This subroutine grabs the version number of the file.  No longer used
and is not exported by default from the module.  Replaced by the
get_cvs_version subroutine.

=back

=over 4

=item *

copy_check

Pass the names of two files to this subroutine and it will return '1' if they
are the same size or '0' if otherwise.

=back

=over 4

=item *

mail_maintainer

Mails the logfile from certain script to desired recipients.

Usage:                                                                    
&mail_maintainer(<title>,<maintainer e-mail list>,<logfile>);                                                                                
No return value.

=back

=over 4

=item *
celeaccession

Pass this subroutine the name of a clone and it will return the 
corresponding accession number

=item *
find_database

Pass a list of clones and 'cam' or 'stl' and it will return the clones 
in camace / stlace

=back

=over 4

=item *

release_databases

writes a file detailing the databases used in the current build. 
The contents of this are included in the release letter.
Checks that databases used are not older than those used in previous build.
Emails output and warns if problems

=back

=over 4

=item *

find_file_last_modified

Passed a filename, this returns the date yyyy-mm-dd and time

=back

=over 4

=item *

release_composition

writes a file detailing the sequence composition in the current build.
This is used in the release letter.
Checks the sequence composition of the current genome compared to the last one.
Does various checks on data integrity and flags any problems in the mail sent.

=back

=over 4

=item *

release_wormpep

Compiles release stats of the current Wormpep and writes to a file, later used in release letter.

=back 

=over 4

=item *

check_write_access

Takes a path to an acedb database and returns "yes" if no database/lock.wrm file is present
(i.e. yes, you have write access) and returns "no" if such a file is present.

=back 

=over 4

=item *

check_file

Checks the existence of the specified file, checks that it is readable
and writeable and optionally checks other things. Note that this can
be used to check on a directory as well as normal files.

Example:
$wormbase->check_file("file.out", $log, 
		      minsize => 10, 
		      maxsize => 10000,
		      minlines => 10,
		      maxlines => 1000,
		      line1 => '^\S+\s+\S+',
		      line2 => '^#',
		      lines => ['^#', '^\s$', '^[a-z]+'],
		      );


Arguments:
    - filename to check
    - $log
    - optional hash containing one or more of the following:
      readonly => 1 (allow the file to be readonly)
      samesize => file_name to compare to
      similarsize => file_name to compare to (within 10% of the size)
      minsize => integer number of bytes
      maxsize => integer number of bytes
      minlines => integer number of lines
      maxlines => integer number of lines
      line1 => regular expression that line 1 of the file must match
      line2 => regular expression that line 2 of the file must match
      lines => [reference of list of regular expressions, all other lines must match at least one of these]
      requires => [reference of list of regular expressions, there must be at least one match of each regular expression in the file]

Returns the number of errors found and sets the error flag

=back 

=over 4

=item *

gff_sort


gff_sort reads a GFF file from STDIN , ignores comment lines and blank
lines and prints the remaining lines to STDOUT sorted by the following
keys:

name (column 0)
start (column 3)
end (column 4)

=back 

=over 4

=item *

tace

tace returns the path for tace that is being used

=back 

=over 4

=item *

dbfetch

dbfetch takes arguments:

   name of sequence to find
   name of file containing one or more sequences in Fasta format

It returns the first fasta format sequence from the file whose name
matches the input seqeunce name.

=back 

=over 4


=head2 load_to_datase

=head2 SYNOPSIS

=over4

&load_to_database($database, $file, "tsuser" );

=back

=head2 USAGE

=over4

Loads specified file in to specified acedb database with tsuser as specified :)
If tsuser not set then the file name will be used (no path, and '_' replacing and '.'s )

=back

=cut

