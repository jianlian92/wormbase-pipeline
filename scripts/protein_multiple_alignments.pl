#!/usr/bin/env perl 

use lib $ENV{CVS_DIR};
use Wormbase;
use Getopt::Long;
use DBI;
use strict;

use LSF RaiseError => 0, PrintError => 1, PrintOutput => 0;
use LSF::JobManager;

use File::Which qw(which);

my ($debug,
    $store,
    $test,
    $wb,
    $rdb_user,
    $rdb_pass,
    $rdb_host, 
    $rdb_port,
    $rdb_name,
    $aligner_dir,
    $aligner_exe,
    @species,
    $run_clustal,
    $dump_clustal,
    $ace_database,
    $dontclean);

GetOptions(
  'debug=s'          => \$debug,
  'store=s'          => \$store,
  'test=s'           => \$test,
  'extraspecies=s@'  => \@species,
  'host=s'           => \$rdb_host,
  'port=s'           => \$rdb_port,
  'user=s'           => \$rdb_user,
  'pass=s'           => \$rdb_pass,
  'acedb=s'          => \$ace_database,
  'dontclean'        => \$dontclean,
  'alignerdir'       =>  \$aligner_dir,
  'aligneerexe'      => \$aligner_exe,
  'run'              => \$run_clustal,
  'dump'             => \$dump_clustal,
) ||die(@!);

if ($store) {
  $wb = Storable::retrieve($store) or die('cannot load from storable');
}
else { 
  $wb = Wormbase->new( 
    -debug => $debug, 
    -test => $test);
}

my $log = Log_files->make_build_log($wb);


if (not $run_clustal and not $dump_clustal) {
  $run_clustal = $dump_clustal = 1;
}

$rdb_name = "worm_clw";
$rdb_host = "farmdb1" if not defined $rdb_host;
$rdb_port = "3306" if not defined $rdb_port;
$rdb_user = "wormadmin" if not defined $rdb_user;
$rdb_pass = "worms" if not defined $rdb_pass;
$ace_database = $wb->autoace if not defined $ace_database;

my %species = map { $_ => 1 } @species;
$species{elegans} = 1;

$aligner_exe = "muscle" if not defined $aligner_exe;
if (not defined $aligner_dir) {
  $aligner_dir = which($aligner_exe);
  if (not defined $aligner_dir) {
    $log->die("Could not find '$aligner_exe' on PATH. Exiting\n");
  }
  $aligner_dir =~ s/$aligner_exe$//;
}

my $run_jobs_failed = 0;
if ($run_clustal) {
  my %accessors = $wb->species_accessors;
  $accessors{elegans} = $wb;
  
  # clean out database
  my $prefix = $wb->wormpep_prefix;
  my $dbconn = DBI->connect("DBI:mysql:dbname=${rdb_name};host=${rdb_host};port=${rdb_port}" ,$rdb_user,$rdb_pass);
  
  my $lsf = LSF::JobManager->new();
  
  my $scratch_dir = $wb->build_lsfout;
  my %job_info;
  
  foreach my $species (sort keys %species) {
    $log->write_to("Processing proteins for $species..\n");

    my $prefix = $accessors{$species}->wormpep_prefix;
    
    my $infile = $wb->wormpep . "/" . $wb->pepdir_prefix . "pep" . $wb->version;
    $log->log_and_die("Could not find $infile - you probably did not rebuild $species?") if not -e $infile;
    $log->write_to("Will repopulate for $species using $infile\n");
    
    $dbconn->do("DELETE FROM clustal WHERE peptide_id LIKE \'$prefix\%\'") unless $dontclean;
    
    my $cmd_prefix = "$scratch_dir/clustal.$species.$$.";
    
    my $batch_total = 20;
    for(my $batch_idx = 1; $batch_idx <= $batch_total; $batch_idx++) {
      my $cmd_file = "${cmd_prefix}.${batch_idx}.cmd.csh";
      my $cmd_out  = "${cmd_prefix}.${batch_idx}.lsfout";
      my $job_name = "worm_clustal";
      
      my @bsub_options = (-o => "$cmd_out",
                          -J => $job_name, 
                          -M => 3700,
                          -R => "select[mem>=3700] rusage[mem=3700]");
      
      my $cmd = "clustal_runner.pl" 
          . " -batchid $batch_idx"
          . " -batchtotal $batch_total"
          . " -user $rdb_user"
          . " -pass $rdb_pass"
          . " -host $rdb_host"
          . " -port $rdb_port"
          . " -dbname $rdb_name"
          . " -pepfile $infile"
          . " -database $ace_database"
          . " -alignerdir $aligner_dir";
      if ($store) {
        $cmd = $wb->build_cmd_line($cmd, $store);
      } else {
        $cmd = $wb->build_cmd($cmd);
      }
      open(my $cmd_fh, ">$cmd_file") or $log->log_and_die("Could not open $cmd_file for writing\n");
      print $cmd_fh "#!/bin/csh\n";
      print $cmd_fh "$cmd\n";
      close($cmd_fh);
      chmod 0777, $cmd_file;
      
      my $job_obj = $lsf->submit(@bsub_options, $cmd_file);
      if (defined $job_obj) {
        $job_info{$job_obj->id} = {
          output_file => $cmd_out,
          command_file => $cmd_file,
        }
      } else {
        $log->log_and_die("Could not submit job $cmd_file\n");
      }
    }
  }
  $lsf->wait_all_children( history => 1 );
  
  $log->write_to("All clustal jobs have completed!\n");
  for my $job ( $lsf->jobs ) {    # much quicker if history is pre-cached
    my $job_cmd =  $job_info{$job->id}->{command_file};
    my $job_out =  $job_info{$job->id}->{output_file};
    
    if ($job->history->exit_status == 0) {
      unlink $job_cmd, $job_out;   
    } else {    
      $log->error("$job exited non zero: check $job_out and re-run $job_cmd before dumping\n");
      $run_jobs_failed++;
    }
  }
}

if ($run_jobs_failed) {
  $log->log_and_die("Some clustal jobs failed; you will need to re-run these manually before dumping\n");
}


if ($dump_clustal) {
  my $outdir = $wb->misc_output;
  my $outfile = "$outdir/wormpep_clw.sql.gz";
  my $cmd = "mysqldump -u $rdb_user -p$rdb_pass -h $rdb_host -P $rdb_port $rdb_name | gzip > $outfile";
  $wb->run_command($cmd, $log);
}

$log->mail;
exit(0);