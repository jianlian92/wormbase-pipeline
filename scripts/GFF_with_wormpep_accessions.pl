#!/usr/local/bin/perl5.6.1 -w
#
# GFF_with_wormpep_accessions.pl
#
# By dl1

# Last updated on: $Date: 2002-12-09 13:11:35 $
# Last updtaed by: $Author: ck1 $

$0 =~ m/\/([^\/]+)$/;
system ("touch /wormsrv2/logs/history/$0.`date +%y%m%d`");

use strict;
use Ace;


$|=1;

my $file   = shift;
my $wormdb = "/wormsrv2/autoace";

my $db = Ace->connect(-path=>$wormdb) || do { print "Connection failure: ",Ace->error; die();};

open (GFF, "<$file") || die "Can't open GFF file\n\n";
while (<GFF>) {

    next if (/^\#/);
    
    chomp;

    my @gff = split (/\t/,$_);
    
    (my $gen_can) = $gff[8] =~ /Sequence \"(\S+)\"/; 

    my $obj = $db->fetch(Sequence=>$gen_can);
    if (!defined ($obj)) {
        print "Could not fetch sequence '$gen_can'\n";
        next;
    }

    my $acc = $obj->Corresponding_protein(1);
    $acc =~ s/WP\://g;

    if ($acc ne "") {
	$acc =~ s/WP\://g;
	print "$_ wp_acc=$acc\n";
    }
    else {  # could be a tRNA
	print "$_\n";
    }
    undef ($acc); 

    $obj->DESTROY();

}
close GFF;
$db->close;
exit(0);

