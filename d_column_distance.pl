#!/usr/bin/perl
#
# column_distance.pl
#
# This program creates a "column-formatted" distance file.
# It can break large files into mulitple jobs, each job saving to its
# part to its own file. the parts must then be appended together.
#
# This allows the program to reduce the total amount of RAM necessary to create
# the matrices and greatly speeds up the creation of the larges distance matrices.
#
# The program calculates distance more simply than dnadist and saves distance
# matrices on a per fasta input file basis. MOTHUR can then be used to make OTUs.
#
# The distance calculation is performed as follows.
#
#    D = (MM-AMMscore) / TN
#
# where D = distance, MM = mismatches, TN = total nucleotides (matched or not),
# AMMscore = Sum all: (ambiguous base) / (number of abiguities).
# Eg., AMMscore for Y-C and H-A mismatches, both on the same sequence = 1/2 + 1/3.
# End gaps are not counted as a mismatch.  However, all internal gaps are counted
# as a mismatch (unless a corresponding gap exists in the other sequence).
#
# No (evolutionary) assumptions about base changes are made - it's just pure and
# simple differences.
#
#
# Usage: perl column_distance.pl
#
# Usage: (example to break a file into 3 pieces and operate on the first piece)
# perl column_distance.pl Bacteria.Bacteroidetes.Bacteroidetes.Bacteroidales.Bacteroidaceae_Bacteroides.fa 3 1
#
#
# Note: if you have Torque runing on a cluster, use column_distance_qsub.pl to automate this program


use strict;
use Cwd;
use Bio::SeqIO;
use Config::Tiny;

my $largestsfile="large_files_skiped_by_column_distance.txt";#file to contain the names of large files

my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'probeset.conf' );
my $currentdir = getcwd;
my $loaddir = $currentdir."/".$Config->{remove_duplicate_sequences}->{savedir}."/";
my $savedir = $currentdir."/".$Config->{column_distance}->{savedir}."/";
my $minsize = $Config->{column_distance}->{minsize};
my $maxsize = $Config->{column_distance}->{maxsize};
unless( -d $loaddir ) {
	die "Error: specified directory of masked fasta files does not exist.\n";
}
unless( -d $savedir ) {
	mkdir $savedir || die "Error: unable to create directory $savedir.";
}

#set special Perl variables for printing
$,="\n";
#$|=1;



#command line options. used for largest files
#$dothisfileonly=name of a single file to process
#$pieces=number of pieces to break the job into
#$piece=which piece this job should do
my ($dothisfileonly, $pieces, $piece) = @ARGV;


#default file sizes to operate on. files larger than $maxsize
#are skipped, and their names are written to a separate file
#so they can be processed individually, and broken into parts
$minsize=1 unless(defined $minsize);
$maxsize=10000000 unless(defined $maxsize);

#get filenames
my @files = _get_filenames($loaddir);
@files = grep { /\.fa$/ } sort @files;

#separate large and small files
my @smallfiles = grep { (-s $loaddir.$_) > $minsize && (-s $loaddir.$_) < $maxsize } @files;
my @largefiles = grep { (-s $loaddir.$_) > $maxsize } @files;
my @largesizes = map { (-s $loaddir.$_) } @largefiles;
push @largesizes, @largefiles;
_save_names(\@largesizes,$largestsfile) unless(defined $dothisfileonly);

#get filenames of finished distance matrix files so we don't redo them
my @alreadymadefiles = _get_filenames($savedir);
@alreadymadefiles = grep { s/\.dm/\.fa/ } sort @alreadymadefiles;


#make a final list
my @filestodo;
foreach my $f( @smallfiles ) {
	push @filestodo, $f unless( grep{ /$f/ } @alreadymadefiles );
}


#sort files by size. we'll start with the smallest and move to largest
my @filestodo = sort { (-s $loaddir.$a) <=> (-s $loaddir.$b)  } @filestodo;


#but if user has set $dothisfileonly via command line then we'll only do that one
@filestodo=$dothisfileonly if(defined $dothisfileonly);


print "Loading file(s) from $loaddir\n";
print "Loaded ".(scalar @filestodo)." files\n";



#process files
foreach my $file( @filestodo ) {
	
	my $filesize = -s $loaddir.$file;
	print $file.":  ".$filesize." bytes\n";
	#my @diffs;#will be an array of arrays

	my $SEqs = _get_all_sequences($loaddir.$file);#HAsh ref

	my @rdpids = grep { /\w\d{9}/ } sort keys %$SEqs;#get only RDP IDs
	next unless( @rdpids > 1);#no distance matrix possible for only one sequence

	if(defined $pieces)
	{
		#make one piece of several pieces
		_make_distance_matrices($file, $SEqs, \@rdpids, $pieces, $piece);
	}
	else
	{
		#make just one piece
		_make_distance_matrices($file, $SEqs, \@rdpids, 1, 1);
	}

}

print "\nSaved files to $savedir\n";


exit;





#######################
##### subroutines #####
#######################
sub _make_distance_matrices 
{	
	my ($file, $SEqs, $rdpids_aref, $pieces, $piece) = @_;
	die "The piece you want to do is out of range!\n" if($piece > $pieces || $piece < 1);

	my @stopstarts = __get_start_points($rdpids_aref, $pieces);

	print "Tot seqs: ".(scalar @$rdpids_aref)."\n";
	my $idx = $piece-1;
	print "Piece $piece of $pieces starts at index ".$stopstarts[$idx]." and stops at index ".($stopstarts[$idx+1]-1)."\n" if($pieces > 1);

	my $thisfile = $file;

	#make numbered part names if more than 1 part
	if($pieces > 1) {
		$thisfile =~ s/\.fa//;
		my $thispiece = sprintf("%02d", $piece);
		$thisfile = $thisfile."--".$thispiece.".dmpart";
	}
	#don't if only 1 part
	else {
		$thisfile =~ s/\.fa/\.dm/;
	}

	print $thisfile."\n";

	open( FILE, ">".$savedir.$thisfile ) || die "Can't open the file: $thisfile\n$!\n";

	my $t1 = time();


	#calculate diffs and save in column-formatted distance matrix for MOTHUR
	for( my $outeridx=$stopstarts[$idx]; $outeridx<$stopstarts[$idx+1]; $outeridx++ ) {

		my $outerseq = $$SEqs{$$rdpids_aref[$outeridx]};
		for( my $inneridx=$outeridx+1; $inneridx<@$rdpids_aref; $inneridx++ ) {
			my $diff = _calculate_difference( $outerseq, $$SEqs{$$rdpids_aref[$inneridx]} );
			$diff = sprintf("%.5f", $diff);
			print FILE $$rdpids_aref[$outeridx]."\t".$$rdpids_aref[$inneridx]."\t".$diff."\n";
		}
	}
	close FILE;

	my $t2 = time();
	my $tot = $t2-$t1;
	my $totpairs = ( (scalar @$rdpids_aref)*((scalar @$rdpids_aref)-1) ) / 2;
	my $timeperpair = $tot/$totpairs;
	print "Time: ".$tot." sec. Time per pairwise calc: ".$timeperpair."\n" if($tot > 1);
}



sub __get_start_points
{
	my ($rdpids_aref, $pieces) = @_;

	my $totseqs = scalar @$rdpids_aref;
	my $totdists = $totseqs * ($totseqs-1) / 2;
	my $distsperpiece = int($totdists/$pieces);# a rough target for the number of distances to calculate

	my @stopstarts;
	$stopstarts[0]=0;#must always start at the zero index
	my $additionalpairs = $totseqs-1;#number of pairs to do when comparing all sequences to just the first sequence
	my $idx=0;

	#create an array of start points (indexes in @$rdpids_aref) for each piece
	for(0 .. ($pieces-1))
	{
	        my $currentpairs=0;
	        while($currentpairs < $distsperpiece && $additionalpairs > 0)
	        {
	                $currentpairs += $additionalpairs;
		        $additionalpairs--;#this decreases as each sequence is compared to all those after it
		        $idx++;
		}
		push @stopstarts, $idx;

	}
	$stopstarts[$#stopstarts]++;
	return @stopstarts;
}



sub _calculate_difference
{
    my ($s1,$s2) = @_;
    $s1=uc($s1); $s2=uc($s2);
    my ($combined_mismatches, $num_nucleotides) = __get_combined_mismatches($s1,$s2);
    my $tot_mismatches = length($combined_mismatches) / 2;
    return ($tot_mismatches/$num_nucleotides);
}




# mismatch pairs are returned as a single sequence
sub __get_combined_mismatches 
{
    my ($s1,$s2) = @_;
	#we first trim the ends of dashes because a base/dash mismatch is not counted as a mismatch on the ends    
    #trim 5' dashes
    my ($z1) = $s1 =~ /^(-*)/o;
    my ($z2) = $s2 =~ /^(-*)/o;
    my $cutlengthL = length($z1) >= length($z2) ? length($z1):length($z2);#get end with most dashes
    substr($s1,0,$cutlengthL, "");
    substr($s2,0,$cutlengthL, "");
    #trim 3' dashes
    my ($z3) = $s1 =~ /(-*)$/o;
    my ($z4) = $s2 =~ /(-*)$/o;
    my $cutlengthR = length($z3) >= length($z4) ? length($z3):length($z4);
    my $p = length($s1) - $cutlengthR;
    substr($s1,$p,$cutlengthR, "");
    substr($s2,$p,$cutlengthR, "");

    my ($combined_mms, $num_nucleotides) = __combine_mismatches($s1, $s2);

    return ($combined_mms, $num_nucleotides);
}



sub __combine_mismatches
{
	my ($s1, $s2) = @_;
	my $num_nucleotides = length $s1;#get length of alignment
	my $idx = $num_nucleotides-1;
	my $cmms="";
	foreach(0..$idx)
	{
		#if mismatched, combine into a 2 char string and concatenate with other mismatches
		if( substr($s1,$_,1) ne substr($s2,$_,1) )
		{
			$cmms = $cmms.substr($s1,$_,1).substr($s2,$_,1);
		}
		#else these are matched. but if they are dashes we must decrement the nucleotide counter to get the true alignment length
		else
		{
			$num_nucleotides-- if(substr($s1,$_,1) eq "-");# only need to check one of them
		}
	}
	return ($cmms, $num_nucleotides);
}



sub _get_filenames
{
    my $dir = shift;
    opendir(IMD, $dir) || die("Cannot open directory");
    my @files = readdir(IMD);
    shift @files;#get rid of "." and ".." files
    shift @files;
    close IMD;
    return @files;
}



sub _save_names 
{
	my ($names_aref, $file) = @_;
	return unless(scalar @$names_aref > 0);
	open(FILE, ">".$file) || die "Error: the file $file cannot be opened!\n$!\n";
	my $names = (scalar @$names_aref) / 2;
	for(my $i=0; $i<$names; $i++) {
		print FILE $$names_aref[$i]."\t".$$names_aref[$i+$names]."\n";
	}	
	close FILE;
}



sub _get_all_sequences
{
	my $fafile = shift;
	my %SEqs;
	my $seqio_obj = Bio::SeqIO->new(-file => $fafile, -format => "fasta" );
	my $seq_obj;
	while( $seq_obj = $seqio_obj->next_seq() )
	{
		$SEqs{ $seq_obj->primary_id() } = $seq_obj->seq;
	}
	return \%SEqs;
}

