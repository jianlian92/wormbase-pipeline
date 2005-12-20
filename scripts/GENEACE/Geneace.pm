#!/usr/local/bin/perl5.8.0 -w
# Last updated by $Author: mh6 $
# Last updated on: $Date: 2005-12-20 15:52:50 $

package Geneace;

use lib $ENV{'CVS_DIR'};
use Ace;
use Wormbase;
use Coords_converter;
use strict;

# constant stuff (hopefully not modified anywhere)
my $def_dir = '/nfs/disk100/wormpub/DATABASES/geneace/wquery';           # location of table-maker definitions
my $curr_db = '/nfs/disk100/wormpub/DATABASES/current_DB';
my $geneace_dir = '/nfs/disk100/wormpub/DATABASES/geneace';

sub init {
  my ($class,$wormbase) = @_;
  
  $wormbase= Wormbase->new() if !($wormbase); # crude hack
  my $this= {
	  tace => $wormbase->tace
  	};
  # set class variables
  bless($this, $class);
}

sub get_geneace_db_handle {
  my $self = shift;
  my $db = Ace->connect(-path  => $geneace_dir,
		        -program =>$self->{tace}) || die "Connection failure";
  return $db;
}

# accessors, that are not used as far as i can see
sub geneace {return $geneace_dir}
sub curr_db {return $curr_db}
sub test_geneace {return  '/nfs/disk100/wormpub/DATABASES/TEST_DBs/CK1TEST'}

sub gene_info {
  my ($this, $db, $option) = @_;
  shift;

  $db = "/nfs/disk100/wormpub/DATABASES/geneace" if !$db;
  print "----- Doing Gene id <-> Gene_name conversion based on $db ... -----\n\n";

  my $outfile = "$geneace_dir/CHECKS/gene_info.tmp"; `chmod 777 $outfile`;
  my (%gene_info, %seqs_to_Gene_id);

  my $gene_info="Table-maker -o $outfile -p \"$def_dir/geneace_gene_info.def\"\nquit\n";

  open (FH, "echo '$gene_info' | $this->{tace} $db |") || die "Couldn't access $db\n";
  while(<FH>){}

  my @gene_info = `cut -f 1,2 $outfile`;
  foreach (@gene_info){
    chomp $_;
    my ($gene, $cgc_name) = split(/\s+/, $_);
    $gene =~ s/\"//g;
    $cgc_name =~ s/\"//g;
    $gene_info{$gene}{'CGC_name'} = $cgc_name if $cgc_name;
    $gene_info{$cgc_name}{'Gene'} = $gene     if $cgc_name;
  }

  @gene_info = `cut -f 1,3 $outfile`;
  foreach (@gene_info){
    chomp $_;
    my ($gene, $seq_name) = split(/\s+/, $_);
    $gene =~ s/\"//g;
    $seq_name =~ s/\"//g;
    $gene_info{$gene}{'Sequence_name'} = $seq_name if $seq_name;
    $gene_info{$seq_name}{'Gene'}      = $gene     if $seq_name;
  }

  @gene_info = `cut -f 1,4 $outfile`;
  foreach (@gene_info){
    chomp $_;
    my ($gene, $other_name) = split(/\s+/, $_);
    $gene =~ s/\"//g;
    $other_name =~ s/\"//g;
    push(@{$gene_info{$gene}{'Other_name'}}, $other_name) if $other_name;
    $gene_info{$other_name}{'Gene'} = $gene               if $other_name;
  }

  @gene_info = `cut -f 1,5 $outfile`;
  foreach (@gene_info){
    chomp $_;
    my ($gene, $public_name) = split(/\s+/, $_);
    $gene =~ s/\"//g;
    $public_name =~ s/\"//g;
    $gene_info{$gene}{'Public_name'} = $public_name if $public_name;
    $gene_info{$public_name}{'Gene'} = $gene        if $public_name;
  }

  return (\%gene_info, \%seqs_to_Gene_id) if $option;
  return %gene_info if !$option;
}

sub parse_inferred_multi_pt_obj {
  print "\n\nYou have just called a subroutine in Genace.pm that was assumed to be redundant, please notify mt3/pad as whatever you were doing will not have worked correctly.\n\n";
  my ($this, $version) = @_;
  my ($multi_obj, %locus_multi, $locus);
  my $multi_file = glob("/nfs/disk100/wormpub/DATABASES/geneace/JAH_DATA/MULTI_PT_INFERRED/inferred_multi_pt_obj_WS$version");
  my @multi_file = `cat $multi_file`;

  foreach (@multi_file){
    chomp;
    if ($_ =~ /^Multi_pt_data : (\d+)/){
      $multi_obj = $1;
    }
    if ($_ =~ /^Combined Locus \"(.+)\" 1 Locus \"(.+)\" 1 Locus \"(.+)\"/){
      $locus = $2;
      $locus_multi{$locus} = $multi_obj;
    }
  }
  return %locus_multi;
}


sub other_name {
  my ($this, $db, $option) = @_; # $db is db handle
  my (%main_other, %other_main);

  push( my @result, $db->find("Find Gene_name * where Other_name_for AND !(Cb-* OR Cr-*)") );
  if ($option eq "main_other"){
    foreach(@result){
      push(@{$main_other{$_ -> Other_name_for(1)}}, $_);
    }
    return %main_other;
  }
  if ($option eq "other_main"){
    foreach(@result){
      push( @{$other_main{$_}}, $_ -> Other_name_for(1) );
    }
    return %other_main;
  }
  if ($option eq "other"){
    return @result;
  }
  if (!$option){
    print "You need to specify parameters: 'main_other' or 'other_main' or 'other'.  First 2 params. returns hashes (CGC_name->Other_name / Other_name->CGC_name), last one returns an array of all Other_names\n";
  }
}

sub cgc_name_is_also_other_name {
  my ($this, $db) = @_; # $db is db handle
  push( my @exceptions, $db->find("Find Gene_name * CGC_name_for & Other_name_for") );
  return @exceptions;
}

sub gene_id_has_multi_pt {
  my ($this, $db) = @_;
  push( my @gene_ids_have_multi, $db->find("Find Gene * where Multi_point") );

  my %gene_id_2_multi;
  foreach (@gene_ids_have_multi){
    push(@{$gene_id_2_multi{$_}}, $_ -> Multi_point(1) );
  }
  return %gene_id_2_multi;
}

sub clone_to_lab {
  my $this = shift;
  my %clone_lab;

  my $clone_to_lab="Table-maker -p \"$def_dir/clone_to_lab.def\"\nquit\n";

  open (FH, "echo '$clone_to_lab' | $this->{tace} $curr_db |") || die "Couldn't access $curr_db\n";
  while (<FH>){
    chomp $_;
    if ($_ =~ /\"(.+)\"\s+\"(.+)\"/){
      $clone_lab{$1} = $2;
    }
  }
  return %clone_lab;
}

sub upload_database {
  my($this, $db_dir, $command, $tsuser, $log) = @_;
  open (Load_GA,"| $this->{tace} -tsuser \"$tsuser\" $db_dir >> $log") || die "Failed to upload to $db_dir";
  print Load_GA $command;
  close Load_GA;
}

sub array_comp {

  my ($this, $ary1_ref, $ary2_ref, $option)=@_;
  my(@union, @isect, @diff, %union, %isect, %count, $e);
  @union=@isect=@diff=();
  %union=%isect=();
  %count=();
  foreach $e(@$ary1_ref, @$ary2_ref){
    $count{$e}++;
  }
  foreach $e (keys %count){
    push (@union, $e);
    if ($count{$e}==2){push @isect, $e;}
    else {push @diff, $e;}
  } 
  return \@diff, \@isect, \@union if !$option;
  return @diff if $option eq "diff";
  return @isect if $option eq "same";
  return @union if $option eq "union";
}

sub get_clone_chrom_coords {

  my %clone_info;
  my $gff_version = get_wormbase_version() - 1;  # current_DB version
  my @clone_coords = `cut -f 1,4,5,9 /wormsrv2/autoace/GFF_SPLITS/WS$gff_version/CHROMOSOME_*.clone_acc.gff`;
  foreach (@clone_coords){
    chomp;
    my ($chrom, $start, $end, $nineth) = split(/\t+/, $_);
    $chrom =~ s/[A-Z]+_//;
    $nineth =~ /S.+\s+\"(.+)\".+/;
    my $clone = $1;
    push(@{$clone_info{$clone}}, $chrom, $start, $end);
  }
  return %clone_info;
}

sub get_unique_from_array {
  my ($this, @array) = @_;
  my %seen=();
  my @new_array_no_dup;
  foreach (@array){push(@new_array_no_dup, $_) unless $seen{$_}++}
  return @new_array_no_dup;
}


sub get_non_Transposon_alleles {
  my ($this, $db) = @_;
  my (%Alleles, @alleles);

  push(@alleles, $db->find("Find Variation * where !Transposon_insertion") );
  foreach (@alleles){$Alleles{$_}++}
  return %Alleles;
}


sub allele_to_gene_id {
  my ($this, $db)=@_;
  my %allele_to_gene_id;

  my $def="Table-maker -p \"$def_dir/allele_to_gene_id.def\"\nquit\n";

  open (FH, "echo '$def' | $this->{tace} $db | ") || die "Couldn't access geneace\n";
  while (<FH>){
    chomp$_;
    if ($_ =~ /^\"(.+)\"\s+\"(.+)\"/){
      push(@{$allele_to_gene_id{$2}}, $1);  # $2 is allele_designation $1 is LAB	
    }
  }
  return %allele_to_gene_id;

}

sub gene_id_status {
  my ($this)=shift;
  my (%gene_id_is_live, @live, %gene_id_is_not_live, @non_live);
  my $db = get_geneace_db_handle();

  push(@live, $db->find("Find Gene * where Live") );
  push(@non_live, $db->find("Find Gene * where !Live") );
  foreach (@live){$gene_id_is_live{$_}++};
  foreach (@non_live){
    $gene_id_is_not_live{$_} = $_ -> Merged_into;
  }
  return \%gene_id_is_live, \%gene_id_is_not_live;
}

sub get_last_gene_id {

  my $db = get_geneace_db_handle();
  my @gene_ids = $db->fetch('Gene'=>'*');
  my $last_gene_id_num = $gene_ids[-1];
  $last_gene_id_num =~ s/WBGene0+//;
  return $last_gene_id_num;
}

sub get_WBPersonID {
  my $this= shift;
  # this is just a simple hash and its name look up functionality is only limited to first_name, last_name
  # and has not yet extended for standard_name, other_name, also_known_as, etc
  # but enough for now to do Jonathan's lab update.
  # note that some pi name may not be covnerted to WBPersonID due to this limitation (eg, Dave, David is not 
  # treated as identical, there for David Someone is not Dave Someone, although it would be in the database
  # DO THIS BY HAND FOR NOW

  my $person="Table-maker -p \"$def_dir/get_WBPersonID_fn_ln.def\"\nquit\n";
  open (FH, "echo '$person' | $this->{tace} $geneace_dir |") || die "Couldn't access $geneace_dir\n";

  my %WBPerson_id;
  while (<FH>){
    chomp $_;
    if ($_ =~ /\"(.+)\"\s+\"(.+)\"\s+\"(.+)\"/){  # $1(WBPersonxx), $2(first_name), $3(last_name)
      $WBPerson_id{$3.", ".$2} = $1;
    }
  }
  return %WBPerson_id;
}

1;
