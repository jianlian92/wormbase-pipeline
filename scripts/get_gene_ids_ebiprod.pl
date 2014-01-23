#!/usr/bin/env perl -w

use DBI;
use strict;
use Getopt::Long;

my ($org_id, $ena_db, $verbose); 

&GetOptions(
  'enadb=s'         => \$ena_db,
  'orgid=s'         => \$org_id,
  'verbose'         => \$verbose,
    );


if (
    not defined $org_id or
    not defined $ena_db) {
  die "Incorrect invocation: you must supply -enadb -uniprotdb and -orgid\n";
}


my %attr   = ( PrintError => 0,
               RaiseError => 0,
               AutoCommit => 0 );


##############
# Query ENA
#############

my $ena_dbh = &get_ena_dbh();

# locus_tag = 84
# standard name (wormbase transcript/CDS/pseudogene name) = 23
my $ena_sql =  "SELECT d.primaryacc#, sf.featid, fq.fqualid, fq.text"
    . " FROM dbentry d, cv_dataclass dc,  bioseq b, seqfeature sf, feature_qualifiers fq"
    . " WHERE d.primaryacc# IN ("
    . "   SELECT primaryacc#"
    . "   FROM dbentry" 
    . "   JOIN sourcefeature USING (bioseqid)"
    . "   WHERE organism = $org_id"
    . "   AND project# = 1"
    . "   AND statusid = 4)"
    . " AND d.dataclass = dc.dataclass"
    . " AND dc.description = 'Standard'"
    . " AND d.bioseqid = b.seqid"
    . " AND b.seqid = sf.bioseqid"
    . " AND sf.featid  = fq.featid"
    . " AND fq.fqualid IN (23, 84, 12)";

    
my $ena_sth = $ena_dbh->prepare($ena_sql) or die "Can't prepare statement: $DBI::errstr";

print STDERR "Doing primary lookup of locus_tag entries in ENA ORACLE database...\n" if $verbose;

$ena_sth->execute or die "Can't execute statement: $DBI::errstr";

my (%feats, %g_data);

while ( my ($clone_acc, $feat_id, $qual_id, $qual_val ) = $ena_sth->fetchrow_array ) {
  $feats{$feat_id}->{$qual_id} = $qual_val;
  $feats{$feat_id}->{clone_acc} = $clone_acc;
}
die $ena_sth->errstr if $ena_sth->err;
$ena_sth->finish;
$ena_dbh->disconnect;

foreach my $fid (keys %feats) {
  if (exists $feats{$fid}->{"23"}) {
    if (exists $feats{$fid}->{"84"}) {
      $g_data{$feats{$fid}->{"23"}}->{locus_tag} = $feats{$fid}->{"84"};
    } 
    if (exists $feats{$fid}->{"12"}) {
      $g_data{$feats{$fid}->{"23"}}->{gene} = $feats{$fid}->{"12"};
    }
    if (exists $feats{$fid}->{clone_acc}) {
      $g_data{$feats{$fid}->{"23"}}->{clone_acc} = $feats{$fid}->{clone_acc};
    }
  }
}

foreach my $k (keys %g_data) {
  print "$k";
  printf "\t%s", (exists $g_data{$k}->{clone_acc}) ?  $g_data{$k}->{clone_acc} : "."; 
  printf "\t%s", (exists $g_data{$k}->{gene}) ?  $g_data{$k}->{gene} : "."; 
  printf "\t%s", (exists $g_data{$k}->{locus_tag}) ?  $g_data{$k}->{locus_tag} : "."; 
  print "\n";
}

exit(0);



#####################
sub get_ena_dbh {

  my $dbh = DBI->connect("dbi:Oracle:$ena_db", 
                         'ena_reader', 
                         'reader', 
                         \%attr)
      or die "Can't connect to ENA database: $DBI::errstr";

  return $dbh;
}
