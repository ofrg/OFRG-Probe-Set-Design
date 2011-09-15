#!/usr/bin/perl
#
# sequences2matrix_by_otu.pl 
#
# This program uses training sequences made by training_seqs_maker.pl
# (which removes and replaces variable regions in the sequences with a '#' character).
# This program will 'skip' past the '#' chars and only create 'real'
# probes from the highly conserved regions that remain.
#
#
# This program slurps up prepared training data and creates a matrix
# of (range) filtered probe/clone combinations. the output of this program is
# used directly by the best_probes.o (probe design program) written by Gianluca Della Vedova.
#
# The rationale of this program was to eliminate from consideration those probes
# that bound to too few (or too many) clones in the training data. it is hoped that
# the quality of probe sets will be improved by doing this.
#
# The first version of this program was written by Gianluca Della Vedova
#
#
# Usage: sequences2matrix_by_otu.pl
#

use strict;
use Cwd;
use Bio::SeqIO;
use Config::Tiny;


my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'probeset.conf' );
my $currentdir = getcwd;
my $loaddir = $currentdir."/".$Config->{training_seqs_maker}->{savedir}."/";
my $savedir = $currentdir."/".$Config->{sequences2matrix_by_otu}->{savedir}."/";
my $cutoff = $Config->{training_seqs_maker}->{cutoff};
my $loadfile = $Config->{training_seqs_maker}->{savetrainfile}."_c_".$cutoff;#training sequences
my $matrixfilename = $Config->{training_seqs_maker}->{savetrainfile}."_c_$cutoff.matrix";
#the minimum number of OTUs a probe must occur in to be kept. obsolete.
my $min_otus = $Config->{sequences2matrix_by_otu}->{min_otus};
my $probelength = $Config->{sequences2matrix_by_otu}->{probelength};
unless( -d $savedir ) {
	mkdir $savedir || die "Error: unable to create directory $savedir!\n$!\n";
}

$|=1;


my %master_probe_list;
my %otu_probes;

my @phylumh;
my @genush;
my @otuh;
my %otus;

my @sequences;
my $firstOTU=1;#true
my $previousotu=0;

my $nclones_in_this_otu=0;
my $number_clones=0;

print "Opening $loadfile and finding probes...\n";
open( FILE, "<".$loaddir.$loadfile ) || die( "Can't open file $loadfile\n$!\n" );

print "nprobes\n";#header

while (my $line=<FILE>) {
	
	chomp $line;
	$number_clones++;
	
	#extract the list of sequences and possible oligos
	my ($phylum, $phynum, $genus, $gennum, $otu, $rdp_id, $sequence)=split(/\t/, $line,7);
	$sequence = uc($sequence);
	
	if($sequence !~/^[ACGT#]+$/o)	{
		my ($badstuff) = $sequence =~ /([^ACGT#]+)/o;#any chars but these are bad
		print "*".$badstuff."*\n";
		die "Sequence error $number_clones: *$sequence*\n" 
	}
	
	###pass 1: true && false		do not add to list yet
	###pass 2: false && true		do not add to list yet
	###pass N: true && true 		add probes from previous OTU to list now
	if( !exists $otus{$otu} && !$firstOTU ) {
		#if here, we've started a new otu, so process the previous otu's data
		_add_these_probes_to_master_list(\%otu_probes, $previousotu, $nclones_in_this_otu);
		$nclones_in_this_otu=0;
		%otu_probes=();
	}
	$nclones_in_this_otu++;
	$firstOTU=0;
	
	push @phylumh,$phynum;
	push @genush,$gennum;
	push @otuh,$otu;
	push @sequences, $sequence;
	$otus{$otu}++;
	$previousotu=$otu;
	
	
	#find/create probes in this sequence via a sliding window
	my %seq_probes;
	my $length_seq = length($sequence)-$probelength;

	for (my $pos=0; $pos<=$length_seq; $pos++) {
		my $oligo=substr($sequence,$pos,$probelength);
		#$seq_probes{$oligo}++;
		$otu_probes{$oligo}++ unless( $oligo =~ /#/ );#do not make probes that span (removed) variable regions
	}
}
close FILE;



print "Sorting probes by OTU binding amounts...\n";
# build a hash of how many OTUs each probe is found in
my %probeOTUbindingamounts;
foreach my $probe( keys %master_probe_list ) {
	$probeOTUbindingamounts{$probe} = scalar keys %{$master_probe_list{$probe}};
}
# get the list of probes, sorted (most to least) on how many OTUs it is found
my @probes_by_sorted_bindings = sort{ $probeOTUbindingamounts{$b}<=>$probeOTUbindingamounts{$a} } keys %probeOTUbindingamounts;


# notify user
print "Master probe list complete.\n";
print "There are a total of ".scalar @probes_by_sorted_bindings." probes\n";

my $usernum = "";
my $lastusernum;
my $bindingsforthisprobe;

# ask the user how many probes they want in the matrix #
while( $usernum !~ /q/i ) {

	$lastusernum=$usernum;
	print "Enter the number of most conserved probes to keep (or enter 'q' to continue):\n";
	$usernum = <>;
	chomp $usernum;
	my $probecounts=0;
	
	if( $usernum =~ /q/i ) {
		if( $lastusernum < 0 
			|| $lastusernum > @probes_by_sorted_bindings 
			|| $lastusernum =~ /[^0-9]/
			|| $lastusernum eq ""
			) {
			print "\nThe number of probes you have chosen is out of bounds. Please try a different number.\n";
			$usernum="";
			next;
		}
	}
}

my @probesformatrix = @probes_by_sorted_bindings[0 .. ($lastusernum-1)];

print "Writing probes to file...\n";

my $numprbs = "_p".$lastusernum."_cut";
$matrixfilename =~ s/_c_/$numprbs/;

open(FILEOUT, ">", $savedir.$matrixfilename) || die "Can't open file: $savedir.$matrixfilename\n$!\n";
print FILEOUT $number_clones."\n";

#first, create the per probe fingerprints across each clone (columns)
my $pcount=0;


foreach my $probe( sort @probesformatrix ) {
#for my $probe (sort keys %keeperprobes) {
	
	$pcount++;
	print $pcount." ";
	print FILEOUT $probe."\n";
	#$probe = _get_real_binder($probe);# this can be used to mimic partial binding for a probe
	
	for my $clone (@sequences) {
		my $probe_binds_this_clone = scalar ($clone=~/$probe/) || 0;#1 or 0
		print FILEOUT $probe_binds_this_clone." ";
	}
	print FILEOUT "\n";
}
print "\n";

# The last three rows in the output file specify, for each clone, the phylum,
# genus and OTU to which it belongs

print FILEOUT join(' ', @phylumh)."\n";
print FILEOUT join(' ', @genush)."\n";
print FILEOUT join(' ', @otuh)."\n";
close FILEOUT;
print "Matrix file $matrixfilename completed.\n";


exit;






#####################
#### Subroutines ####
#####################

sub _add_these_probes_to_master_list {
	
	my $otu_probes_href = shift;
	my $otunum = shift;
	my $nclones_in_this_otu = shift;
	my $keptcount=0;
	return if($nclones_in_this_otu < 0);
	
	foreach my $probe(keys %$otu_probes_href) {
		##check for 'bad' probe characteristics and skip if found
		#'bad' defined as 3 consecutive 'A's on the 5' end or 4 consecutive bases anywhere
		next if( $probe =~ /^AAA/ || $probe =~ /(\w)\1{4}/);
		
		#key=>probe, value=>\hash{OTUnum}++ (key=>OTUnum, value=>no. of otu's where probe is found)
		${$master_probe_list{$probe}}{$otunum}++;# %master_probe_list
		$keptcount++;
	}

	#this code is not vital, but does provide an indication of the program's progress onscreen
	if($nclones_in_this_otu > 50) {
		my $numprobesinprblist=scalar keys %master_probe_list;
		print $numprobesinprblist."\n";
	}
}


#change the probe sequence into a regex
#allows ambiguous matching of probes to sequences
sub _get_real_binder {
    my $probe = shift;
    my @bases = split(//,$probe);
    my @postoconvertGTs = (0, 9);#this may change as we gather more hyb data
    foreach(@postoconvertGTs) {
        if($bases[$_] =~ /[GT]/i) {$bases[$_] = "[GT]";}
    }
    return join('', @bases);
}

