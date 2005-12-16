#!/usr/local/bin/perl5.8.0 -w
#
# new_wormpep_entries.pl
#
# by Keith Bradnam
#
# Script to find new wormpep entries in the last release of wormpep
# and produce a fasta file of these sequence to load into the wormprot
# mysql database prior for the pre-build pipeline.
#
# Last updated by: $Author: ar2 $
# Last updated on: $Date: 2005-12-16 11:18:55 $


#################################################################################
# variables                                                                     #
#################################################################################

use strict;
use lib -e "/wormsrv2/scripts" ? "/wormsrv2/scripts" : $ENV{'CVS_DIR'};
use Wormbase;
use IO::Handle;
use Getopt::Long;
use Cwd;

##############################
# command-line options       #
##############################

my $help;                # Help/Usage page
my $test;                # for running in test environment ~wormpub/TEST_BUILD

GetOptions ("help"        => \$help,
            "test"        => \$test
           );


&usage if ($help);


 ##############################
 # Script variables (run)     #
 ##############################

my $release; 
if($test){
  $release = "666";
}
else{
  $release = &get_wormbase_version; 
}
my $old_release  = $release -1;

my $release_name; 
if($test){
  $release_name = "666";
}
else{
  $release_name = &get_wormbase_version_name; 
}



##########################################
# Set up database paths                  #
##########################################

# Set up top level base directory which is different if in test mode
# Make all other directories relative to this
my $basedir   = "/wormsrv2";
$basedir      = glob("~wormpub")."/TEST_BUILD" if ($test); 

our $dbfile     = "$basedir/WORMPEP/wormpep${release}/wp.fasta${release}";
our $old_dbfile = "$basedir/WORMPEP/wormpep${old_release}/wp.fasta${old_release}";

# make a hash of wormpep IDs -> peptide sequence for current and previous versions
# of wormpep
our %wormpep;
our %old_wormpep;
&make_hash;
&make_old_wormpep_hash;

# Simple but important check...is the new wp.fasta file bigger than the old one.
# if not then this is serious and should be investigated
my $old_wp_size = keys(%old_wormpep);
my $new_wp_size = keys(%wormpep);


if($old_wp_size > $new_wp_size){
  die "ERROR: WS${release} wp.fasta file appears to have less entries than WS${old_release} wp.fasta file!\n\n";
}

my %proteins_outputted;
 ###############################
 # Main Loop                   #
 ###############################

open (LOG,  ">$basedir/WORMPEP/wormpep${release}/new_entries.$release_name") || die "Couldn't write output file\n";;
open (DIFF, "<$basedir/WORMPEP/wormpep${release}/wormpep.diff${release}") || die "Couldn't read from diff file\n";
while (<DIFF>) {    
  my ($new_acc,$seq);
    if( (/changed:\t\S+\s+\S+ --> (\S+)/) || (/new:\t\S+\s+(\S+)/) || (/reappeared:\t\S+\s+(\S+)/)) {
      $new_acc = $1;
      next if $old_wormpep{$new_acc};
      next if $proteins_outputted{$new_acc};
      print LOG ">$new_acc\n$wormpep{$new_acc}";
      $proteins_outputted{$new_acc}++;
    }
}
close(DIFF);
close(LOG);
exit(0);


##################
# Usage
##################

sub usage {
    system ('perldoc',$0);
    exit;
}

#################################

sub make_hash {
  my $id;
  my $seq;
  open (WP, "<$dbfile") || die "Couldn't read from file\n";
  while (<WP>) {
    if (/^>(\S+)/) {
      chomp;
      my $new_id = $1;
      if ($id) {
	$id =~ /CE0*([1-9]\d*)/ ; 
	$wormpep{$id} = $seq;
      }
      $id = $new_id ; $seq = "" ;
    } 
    elsif (eof) {
      if ($id) {
	$id =~ /CE0*([1-9]\d*)/ ;
	$seq .= $_ ;
	$wormpep{$id} = $seq;
      }
    } 
    else {
      $seq .= $_ ;
    }
  }

  close (WP);
  
}
#################################

sub make_old_wormpep_hash {
  my $id;
  my $seq;
  open (WP, "<$old_dbfile") || die "Couldn't read from file\n";
  while (<WP>) {
    if (/^>(\S+)/) {
      chomp;
      my $new_id = $1;
      if ($id) {
	$id =~ /CE0*([1-9]\d*)/ ; 
	$old_wormpep{$id} = $seq;
      }
      $id = $new_id ; $seq = "" ;
    } 
    elsif (eof) {
      if ($id) {
	$id =~ /CE0*([1-9]\d*)/ ;
	$seq .= $_ ;
	$old_wormpep{$id} = $seq;
      }
    } 
    else {
      $seq .= $_ ;
    }
  }

  close (WP);
  
}


exit(0);


__END__

=pod

=head1 NAME - new_wormpep_entries.pl

=head2 USAGE

This file looks at the wormpep.diff file from the current release of
wormpep and extracts any new peptide sequences which it writes to
a file inside the respective wormpep directory.  This fasta file
is needed by the prebuild process to populate the wormprot mysql
database with the new protein entries.

More specifically, this script looks for genes flagged as 'new',
'changed', or 'reappeared' in the wormpep.diff file.  However, The 
latter two categories may represent genes that have a wormpep protein 
which already exists. In this sense, we don't need to output the protein 
because it will already be in the MySQL database.  This script always 
compares proteins to the wp.fasta file from the previous release, so
if it spots an older CExxxxx identifier it doesn't bother dumping
the sequence as a 'new' protein.
 
Optional arguments:

=over 4

=item *

-h  this help

=back

=cut
