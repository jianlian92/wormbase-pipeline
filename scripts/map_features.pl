#!/usr/local/bin/perl5.8.0 -w          
#
# map_features.pl
#
# by Dan Lawson
#
# This maps features to the genome based on their flanking sequence.
# Uses Ant's Feature_mapper.pm module
#
#
# Last updated by: $Author: klh $                      # These lines will get filled in by cvs and helps us
# Last updated on: $Date: 2011-05-16 11:10:40 $        # quickly see when script was last changed and by whom


$|=1;
use strict;
use lib $ENV{'CVS_DIR'};
use Feature_mapper;
use Wormbase;
use Ace;
use Getopt::Long;
use Modules::Remap_Sequence_Change;


my ($feature, $smap_parent, $clone, $flanking_left, $flanking_right, $coords, $span,$store);

my $help;                    # Help menu
my $debug;                   # Debug mode 
my $verbose;                 # Verbose mode
my $all;                     # Do all the following features:
my $SL1;                     #  SL1 trans-splice leader acceptors
my $SL2;                     #  SL2 trans-splice leader acceptors
my $polyA_site;              #  polyA_site
my $polyA_signal;            #  polyA_signal
my $binding_site;            #  binding_site feature data.
my $binding_site_reg;        #  binding_site_region feature data
my $segmental_duplication;          #  segmental_duplication features
my $genome_sequence_error;   # genome_sequence_error
my $transcription_start_site;# transcription_start_site
my $transcription_end_site;  # transcription_end_site
my $three_prime_UTR;         # three prime UTRs
my $promoter;                # promoter region
my $regulatory_region;       # regulatory region
my $adhoc;                   # Run against a file, output to screen
my $start;
my $stop;
my $test;
my $no_load;

GetOptions (
	    "all"                      => \$all,
	    "SL1"                      => \$SL1,
	    "SL2"                      => \$SL2,
	    "polyA_site"               => \$polyA_site,
	    "polyA_signal"             => \$polyA_signal,
	    "binding_site"             => \$binding_site,
	    "binding_site_reg"         => \$binding_site_reg,
	    "segmental_duplication"    => \$segmental_duplication,
	    "Genome_sequence_error"    => \$genome_sequence_error,
	    "transcription_start_site" => \$transcription_start_site,
	    "transcription_end_site"   => \$transcription_end_site,
	    "three_prime_UTR"          => \$three_prime_UTR,
	    "promoter"                 => \$promoter,
	    "regulatory_region"        => \$regulatory_region,
	    "adhoc=s"                  => \$adhoc,
            "debug=s"                  => \$debug,
            "verbose"                  => \$verbose,
	    "help"                     => \$help,
    	    'store=s'                  => \$store,
	    'test'                     => \$test,
            'noload'                   => \$no_load,
		);

# Help pod if needed
exec ('perldoc',$0) if ($help);

# recreate configuration  
my $wb;
if ($store) { $wb = Storable::retrieve($store) or croak("cant restore wormbase from $store\n") }
else { $wb = Wormbase->new( -debug => $debug, 
			    -test  => $test 
			    ) }

my $log = Log_files->make_build_log($wb);

#######################
# Remapping stuff
#######################

# some database paths
my $currentdb = $wb->database('current');
my $version = $wb->get_wormbase_version;

print "Getting mapping data for WS$version\n";
my @mapping_data = Remap_Sequence_Change::read_mapping_data($version - 1, $version, $wb->species);




#######################
# ACEDB and databases #
#######################

my $tace   = $wb->tace;
my $dbdir  = $wb->autoace;
my $outdir = $wb->acefiles;
$log->write_to("// writing to ".$wb->acefiles."\n\n");

# WS version for output files
our ($WS_version) = $wb->get_wormbase_version_name;

# coordinates for Feature_mapper.pm module

my $mapper      = Feature_mapper->new($dbdir,undef, $wb);

# sanity checks for the length of feature types
my %sanity = (
	      'SL1'          => 0,
	      'SL2'          => 0,
	      'polyA_site'   => 0,
	      'polyA_signal_sequence' => 6,
	      'binding_site' => -1,
	      'binding_site_region' => -1,
	      'segmental_duplication' => -1,
	      'Genome_sequence_error' => -1,
	      'transcription_end_site' => -1,
	      'transcription_start_site' => -1,
	      'promoter' => -1,
	      'regulatory_region' => -1,
	      'three_prime_UTR' => -1,
	      );

# queue which Feature types you want to map
my @features2map;
push (@features2map, "SL1")           if (($SL1) || ($all));
push (@features2map, "SL2")           if (($SL2) || ($all));
push (@features2map, "polyA_signal_sequence")  if (($polyA_signal) || ($all));
push (@features2map, "polyA_site")    if (($polyA_site) || ($all));
push (@features2map, "binding_site")  if (($binding_site) || ($all));
push (@features2map, "binding_site_region")  if (($binding_site_reg) || ($all));
push (@features2map, "segmental_duplication")  if (($segmental_duplication) || ($all));
push (@features2map, "Genome_sequence_error")  if (($genome_sequence_error) || ($all));
push (@features2map, "transcription_end_site")  if (($transcription_end_site) || ($all));
push (@features2map, "transcription_start_site")  if (($transcription_start_site) || ($all));
push (@features2map, "promoter")  if (($promoter) || ($all));
push (@features2map, "regulatory_region")  if (($regulatory_region) || ($all));
push (@features2map, "three_prime_UTR")  if (($three_prime_UTR) || ($all));

#############
# main loop #
#############

foreach my $query (@features2map) {

  my $table_file = "/tmp/map_features_table_$query.def";
  $log->write_to("// Mapping $query features\n\n");

  # open output files
  open (OUTPUT, ">$outdir/feature_${query}.ace") or die "Failed to open output file\n" unless ($adhoc);

  # start tace session for input data (or find file for adhoc run)
  if ($adhoc) {
    open (TACE, "<$adhoc") or die "Failed to open input file: $adhoc\n";
    print "// Opening a file for input: $adhoc\n" if ($verbose);
  }
  else {
    my $species_name = $wb->full_name;
    my $table = <<EOF;
Sortcolumn 1

Colonne 1
Width 12
Optional
Visible
Class
Class Feature
From 1
Condition Method = "$query" AND Species = "$species_name"

Colonne 2
Width 12
Optional
Visible
Class Sequence
From 1
Tag Sequence

Colonne 3
Width 12
Optional
Visible
Class
Class Sequence
From 1
Tag Flanking_sequences

Colonne 4
Width 32
Optional
Visible
Text
Right_of 3
Tag  HERE

Colonne 5
Width 32
Optional
Visible
Text
Right_of 4
Tag  HERE

// End of these definitions
EOF
    open (TABLE, ">$table_file") || die "Can't open $table_file: $!";
    print TABLE $table;
    close(TABLE);

    open (TACE, "echo 'Table-maker -p $table_file\nquit\n' | $tace $dbdir | ");
  }
  while (<TACE>) {
    
    # when it finds a good line
    if (/^\"(\S+)\"\s+\"(\S+)\"\s+\"(\S+)\"\s+\"(\S+)\"\s+\"(\S+)\"/) {
      ($feature,$smap_parent,$clone,$flanking_left,$flanking_right) = ($1,$2,$3,$4,$5);
      #print "NEXT FEATURE: $feature,$clone,$flanking_left,$flanking_right\n" if ($debug);

      if ($flanking_left eq "" && $flanking_right eq "") {
	$log->write_to("// WARNING: Feature $feature has no flanking sequence - not mapped\n");
	next;
      }

      my @coords = $mapper->map_feature($smap_parent,$flanking_left,$flanking_right);
      if (!defined $coords[2]) {
	$log->write_to("// ERROR: Can't map feature $feature on clone $clone flanking sequences: $flanking_left $flanking_right\n");
	$log->error;

	my @suggested_fix = $mapper->suggest_fix($feature, $sanity{$query}, $smap_parent, $flanking_left, $flanking_right, $version, @mapping_data);
	if ($suggested_fix[4]) { # FIXED :-)
	  $log->write_to("// Suggested fix for $feature : $suggested_fix[3]\n");
	  $log->write_to("\nFeature : $feature\n");
	  $log->write_to("Flanking_sequences $suggested_fix[0] $suggested_fix[1] $suggested_fix[2]\n");
	  $log->write_to("Remark \"Flanking sequence automatically fixed: $suggested_fix[3]\"\n\n");
	} else { # NOT_FIXED :-(
	  $log->write_to("// $feature : $suggested_fix[3]\n");
	}

	next;
      }
      
      my $new_clone = $coords[0];
      $start = $coords[1];
      $stop  = $coords[2];
      
      # Deal with polyA_signal_sequence features which have the
      # flanking sequences outside of the feature, but
      # Feature_mapper::map_feature expects the flanking sequences to
      # overlap the feature by one base to enable correct mapping of
      # features less than 2bp

      # munge returned coordinates to get the span of the mapped feature
      
      if ($query eq "polyA_signal_sequence") {
	if ($start < $stop) {
	  $start++;
	  $stop--;
	  $span = $stop - $start + 1;
	}
	else {
	  $start--;
	  $stop++;
	  $span = $start - $stop + 1;
	}
      }
      # else deal with butt-ended features (e.g. SL1, SL2 & polyA_site)
      elsif ($start > $stop) {
	$span = $start - $stop - 1;
      }
      else {
	$span = $stop - $start - 1;
      }
      
      # check feature span is sane
      if ( exists $sanity{$query} && (($span == $sanity{$query}) || ($sanity{$query} < 0)) ) {
	
	if ($adhoc) {
	  print "$feature maps to $new_clone $start -> $stop, feature span is $span bp\n";
	}
	else {
	  print OUTPUT "//$feature maps to $new_clone $start -> $stop, feature span is $span bp\n";
	  print OUTPUT "\nSequence : \"$new_clone\"\n";
	  print OUTPUT "Feature_object $feature $start $stop\n\n";

          if ($clone ne $new_clone) {
            $log->write_to("// Feature $feature maps to different clone than suggested $clone -> $new_clone; changing parent\n");
            print OUTPUT "\nFeature : \"$feature\"\n";
            print OUTPUT "Flanking_sequences $new_clone $flanking_left $flanking_right\n\n";
          }
	}
      }
      else {
	$log->write_to("// ERROR: $feature maps to $new_clone $start -> $stop, feature span is $span bp\n");
	$log->error;
      }
    } #_ if match line

    # lines that look like features but there is a problem eg. whitespace in flanks.
    elsif (/^\"(\S+)\"/) {
      $log->write_to("// ERROR: $1 has a problem, please check flanking sequences!! (whitespace is one cause)\n");
      $log->error;
    }
  }				 
  close TACE;	
  unlink $table_file if (-e $table_file);

  $wb->load_to_database($wb->autoace, "$outdir/feature_${query}.ace", "feature_mapping", $log) unless $no_load;

}


close OUTPUT unless ($adhoc);


###############
# hasta luego #
###############

$log->mail();
exit(0);

__END__

=pod

=head2 NAME - map_features.pl

=head1 USAGE

=over 4

=item map_features.pl [-options]

=back

map_features.pl mandatory arguments:

=over 4

=item none

=back

map_features.pl optional arguments:

=over 4

=item -all 

map all of the following feature types:

=item -SL1

map SL1 trans-splice leader acceptor sites (2 bp feature)

=item -SL2

map SL2 trans-splice leader acceptor sites (2 bp feature)

=item -polyA_site

map polyA attachement sites (2 bp feature)

=item -polyA_signal

map polyA signal sequence sites (6 bp feature)

=item -debug <user> 

Queries current_DB rather than autoace

=item -build

Assumes you are building, so therefore loads data into autoace and writes acefiles to
autoace/acefiles
=item -store <storefile>

specifies an storable file with saved options

=item -adhoc <file> 

Queries a flatfile for the Feature data. Flatfile format is
"<feature_name>"  "<clone>" "<flanking_sequence_left>" "<flanking_sequence_right>" 

=item -help      

This help page

=cut
