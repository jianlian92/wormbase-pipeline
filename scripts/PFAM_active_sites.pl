#!/software/bin/perl -w

# Last updated by: $Author: pad $
# Last updated on: $Date: 2008-03-12 14:04:53 $

use strict;                                      
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Log_files;
use Storable;
use DBI;
use Bio::SeqIO;

##############################
# command-line options       #
##############################

my ($help, $debug, $test, $verbose, $store, $wormbase);
my $species = 'elegans';
my ($user, $pass, $update);

GetOptions ("help"       => \$help,
            "debug=s"    => \$debug,
	    	"test"       => \$test,
	    	"verbose"    => \$verbose,
	    	"store:s"    => \$store,
	    	"species:s"  => \$species,
	    	"user:s"	 => \$user,
	    	"pass:s"     => \$pass,
	    	"update"     => \$update
           );

if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
                             -organism=> $species
			     );
}

# in test mode?
if ($test) {
  print "In test mode\n" if ($verbose);

}

# establish log file.
my $log = Log_files->make_build_log($wormbase);
$log->write_to("Getting PFAM active sites for $species\n");


$log->write_to("\tconnecting to worm_pfam:ia64d as $user\n");
my $DB = DBI -> connect("DBI:mysql:worm_pfam:ia64d", $user, $pass, {RaiseError => 1})
    or  $log->log_and_die("cannot connect to db, $DBI::errstr");

&update_database if $update;

my $sth_f = $DB->prepare ( 	q{	
	SELECT pfamseq.pfamseq_id, pfamseq.sequence, pfamseq_markup.residue, markup_key.label, pfamseq_markup.annotation 
	FROM pfamseq,pfamseq_markup, markup_key 
	WHERE pfamseq.ncbi_code = ?
	AND pfamseq.auto_pfamseq = pfamseq_markup.auto_pfamseq 
	AND pfamseq_markup.auto_markup = markup_key.auto_markup;
	  	  } );

$log->write_to("\tExcuting query . .\n");
$sth_f->execute($wormbase->ncbi_tax_id);
my $ref_results = $sth_f->fetchall_arrayref;

my %aa2pepid = $wormbase->FetchData('aa2pepid');
#&makepepseq_hash unless (%aa2pepid);

$log->write_to("\twriting output\n");
open (ACE,">".$wormbase->acefiles."/PFAM_active_sites.ace") or $log->log_and_die("cant open ".$wormbase->acefiles."/PFAM_active_sites.ace :$!");
foreach (@$ref_results) {
	my ($seq_id, $seq, $residue, $method, $annotation) = @$_;
	($method) = $method =~ /^(\w+)/;
	if($method eq "Active") {
		if(defined($annotation) and ($annotation !~ /NULL/)) {
			$method = $annotation;
		}else {
			$method = 'Active_site';
		}
	}
	if( $aa2pepid{$seq} ){
		my $pepid = $wormbase->wormpep_prefix.":".$wormbase->pep_prefix.&pad($aa2pepid{$seq});
		
		print ACE "\nProtein : \"$pepid\"\n";
		print ACE "Motif_homol Active_site \"$method\" 0 $residue $residue 1 1\n"; 
	}
	else {
		$log->write_to("$seq_id sequence not in current set\n");
	}
}


$log->mail();
exit;



sub update_database {
	$log->write_to("\n\nUpdating database from PFAM ftp site\n");
	
	my $ftp = glob("~ftp/pub/databases/Pfam/database_files");
	my @tables = qw(markup_key pfamseq pfamseq_markup);
	foreach my $table (@tables){
		$log->write_to("\tfetching $table.txt\n");
		$wormbase->run_command("cp -f $ftp/$table.txt.gz /tmp/$table.txt.gz", $log);
		
		$log->write_to("\tunzippping /tmp/$table.txt\n");
		$wormbase->run_command("gunzip -f /tmp/$table.txt.gz", $log);

		$log->write_to("\tclearing table $table\n");
		$DB->do("DELETE FROM $table") or $log->log_and_die($DB->errstr."\n");
		
		$log->write_to("\tloading data in to $table\n");		
		$DB->do("LOAD DATA LOCAL INFILE \"/tmp/$table.txt\" INTO TABLE $table") or $log->log_and_die($DB->errstr."\n");
		
		$wormbase->run_command("rm -f /tmp/$table.txt", $log);
	}
	$log->write_to("Database update complete\n\n");
}


sub makepepseq_hash {
	$log->write_to("Updating seq->id hash\n");
	my %cds2pepid = $wormbase->FetchData('cds2pepid');
	my $pepfile = $wormbase->wormpep."/".$wormbase->pepdir_prefix."pep".$wormbase->get_wormbase_version;
	my $seqs = Bio::SeqIO->new('-file' => $pepfile, '-format' => 'fasta');
	while(my $pep = $seqs->next_seq){ 
		$aa2pepid{$pep->seq}=$wormbase->pep_prefix.$cds2pepid{$pep->id};
	}

	#data dump for future
	open (PEP,">".$wormbase->common_data."/pepseq2pepid.dat") or $log->log_and_die("cant Data::Dump ".$wormbase->common_data."/pepseq2pepid.dat :$!\n");
	print PEP Data::Dumper->Dump([\%aa2pepid]);
	close PEP;
}

sub pad {
	my $num = shift;
	return sprintf "%05d" , $num;
}
