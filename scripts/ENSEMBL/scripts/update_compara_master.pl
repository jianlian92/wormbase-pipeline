
use strict;
use Getopt::Long;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Compara::Method;
use Bio::EnsEMBL::Compara::GenomeDB;
use Bio::EnsEMBL::Compara::SpeciesSet;


my (
  @species,
  %species_data,
  $compara_code,
  $collection_name,
  $createmlss,
  $recreatedb,
  $reg_conf,
  $create_tree_mlss,
  $tax_host,
  $tax_port,
  $tax_user,
  $tax_dbname,
  $master_host,
  $master_port, 
  $master_user,
  $master_pass, 
  $master_dbname,
  $sfile,
    ); 
    

GetOptions(
  "reg_conf=s"      => \$reg_conf,
  "masterdbname=s"  => \$master_dbname,
  "taxdbname=s"     => \$tax_dbname,
  "collectionname"  => \$collection_name,
  "comparacode=s"   => \$compara_code,
  "recreate"        => \$recreatedb,
  "treemlss"        => \$create_tree_mlss,
  "species=s@"      => \@species,
  "sfile=s"         => \$sfile,
    );

die("must specify registry conf file on commandline\n") unless($reg_conf);
die("Must specify -reg_conf, -masterdbname") unless $reg_conf and $master_dbname;

Bio::EnsEMBL::Registry->load_all($reg_conf);

#foreach my $dbn (@{Bio::EnsEMBL::Registry->get_all_DBAdaptors}) {
#  print $dbn->dbc->dbname, " ", $dbn->group, "\n";
#}
#exit(0);

$collection_name = "worms" if not defined $collection_name;

#
# 0. Get species data
#
if (defined $sfile) {
  open(my $fh, $sfile) or die "Could not open species file for reading\n";
  while(<$fh>) {
    next if /^\#/;
    /^(\S+)/ and push @species, $1;
  }
} elsif (@species) {
  @species = map { split(/,/, $_) } @species;
} else {
  die "You must supply a species list as a file (-sfile) or with -species X -species Y etc\n";
}

my @core_dbs;
foreach my $species (sort @species) {

  my $dbh = Bio::EnsEMBL::Registry->get_DBAdaptor($species, 'core');
  print STDERR "Got core adaptor for $species\n";
  push @core_dbs, $dbh;
}

if ($recreatedb) { 
  die("When creating the db from scratch, you must give -comparacode") unless $compara_code ;

  $tax_dbname = "ncbi_taxonomy" if not defined $tax_dbname;

  print STDERR "Re-creating database from scratch\n";

  {
    my $mdbh = Bio::EnsEMBL::Registry->get_DBAdaptor($master_dbname, 'compara');
    my $taxdbh =  Bio::EnsEMBL::Registry->get_DBAdaptor($tax_dbname, 'compara');

    $master_host = $mdbh->dbc->host;
    $master_port = $mdbh->dbc->port;
    $master_user = $mdbh->dbc->user;
    $master_pass = $mdbh->dbc->password;
    $master_dbname = $mdbh->dbc->dbname;

    $tax_host = $taxdbh->dbc->host;
    $tax_port = $taxdbh->dbc->port;
    $tax_user = $taxdbh->dbc->user;
    $tax_dbname = $taxdbh->dbc->dbname;
  }

  my $compara_connect = "-u $master_user -p${master_pass} -h $master_host -P $master_port";
  my $cmd = "mysql $compara_connect -e 'DROP DATABASE IF EXISTS $master_dbname; CREATE DATABASE $master_dbname'";
  system($cmd) and die "Could not drop and re-create existing database\n";
  
  $cmd = "cat $compara_code/sql/table.sql | mysql $compara_connect $master_dbname";
  system($cmd) and die "Could not populate new database with compara schema\n"; 
  
  $cmd = "mysqlimport --local $compara_connect $master_dbname  $compara_code/sql/method_link.txt";
  system($cmd) and die "Could not populate new database with method_link entries\n"; 
  
  #
  # Populate ncbi taxonomy tables
  #

  open(my $tgt_fh, "| mysql -u $master_user -p$master_pass -h $master_host -P $master_port -D $master_dbname")
      or die "Could not open pipe to target db $master_dbname\n";
  foreach my $table ('ncbi_taxa_node', 'ncbi_taxa_name') {
    open(my $src_fh, "mysqldump -u $tax_user -h $tax_host -P $tax_port ncbi_taxonomy $table |")
        or die "Could not open mysqldump stream from ncbi_taxonomy\n";
    while(<$src_fh>) {
      print $tgt_fh $_;
    }
  }
  close($tgt_fh) or die "Could not successfully close pipe to target db $master_dbname\n";
}


my $compara_dbh = Bio::EnsEMBL::Registry->get_DBAdaptor($master_dbname, 'compara');


#
# Populate genome_dbs
#
my @genome_dbs;
foreach my $core_db (@core_dbs) {

  my $prod_name = $core_db->get_MetaContainer->get_production_name();

  my $gdb;
  eval {
    $gdb = $compara_dbh->get_GenomeDBAdaptor->fetch_by_name_assembly($prod_name);
  };
  if ($@) {
    # not present; create it
    print STDERR "Creating new GenomeDB for $prod_name\n";
    $gdb = Bio::EnsEMBL::Compara::GenomeDB->new(-db_adaptor => $core_db);
    $compara_dbh->get_GenomeDBAdaptor->store($gdb);
  } else {
    print STDERR "Updating existing GenomeDB for $prod_name\n";
    # update the assembly and genebuild data
    my $gdb_tmp =  Bio::EnsEMBL::Compara::GenomeDB->new(-db_adaptor => $core_db);
    $gdb->assembly($gdb_tmp->assembly);
    $gdb->genebuild($gdb_tmp->genebuild);
    $compara_dbh->get_GenomeDBAdaptor->update($gdb);
  }
  push @genome_dbs, $gdb;
}


#
# Make the species set
#
print STDERR "Storing Species set for collection\n";
my $ss = Bio::EnsEMBL::Compara::SpeciesSet->new( -genome_dbs => \@genome_dbs );
$ss->add_tag("name", "collection-${collection_name}");
$compara_dbh->get_SpeciesSetAdaptor->store($ss);

#
# Finally, add the protein-tree MLSSs
#
if ($create_tree_mlss) {
  # For orthologs
  system("perl $compara_code/scripts/pipeline/create_mlss.pl --compara $master_dbname --reg_conf $reg_conf --collection $collection_name --source wormbase --method_link_type ENSEMBL_ORTHOLOGUES --f --pw") 
      and die "Could not create MLSS for orthologs\n";
  
# For between-species paralogues  
  system("perl $compara_code/scripts/pipeline/create_mlss.pl --compara $master_dbname --reg_conf $reg_conf --collection $collection_name --source wormbase --method_link_type ENSEMBL_PARALOGUES --f --pw") 
      and die "Could not create MLSS for between-species paralogs\n"; 
  
# For same-species paralogues
  system("perl $compara_code/scripts/pipeline/create_mlss.pl --compara $master_dbname --reg_conf $reg_conf --collection $collection_name --source wormbase --method_link_type ENSEMBL_PARALOGUES --f --sg") 
      and die "Could not create MLSS for within-species paralogs\n"; 
  
# For protein trees
  system("perl $compara_code/scripts/pipeline/create_mlss.pl --compara $master_dbname --reg_conf $reg_conf --collection $collection_name --source wormbase --method_link_type PROTEIN_TREES --f") 
      and die "Could not create MLSS for protein trees\n";
}

print STDERR "Updated database\n";
exit(0);

