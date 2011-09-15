#!/usr/bin/perl
#
# remove_duplicate_sequences.pl
#
# this program is for removing duplicate sequences in fasta files
# (files created by remove_variable_regions.pl )
#
# Usage: perl remove_duplicate_sequences.pl
#
#
# TODO: save how many duplicates were found in a .log file for each fasta file


use strict;
use Cwd;
use Bio::SeqIO;
use Config::Tiny;


my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'probeset.conf' );
my $currentdir = getcwd;
my $loaddir = $currentdir."/".$Config->{remove_duplicate_sequences}->{loaddir}."/";
my $savedir = $currentdir."/".$Config->{remove_duplicate_sequences}->{savedir}."/";
unless( -d $loaddir ) {
	die "Error: specified directory for fasta files does not exist.\n$!\n";
}
unless( -d $savedir ) {
	mkdir $savedir || die "Error: unable to create directory $savedir!\n$!\n";
}

print "Loading files from $loaddir\n";

#get filenames
my @files = _get_filenames( $loaddir );
@files = grep { /\.fa$/ } sort @files;

print "Loaded ".(scalar @files)." files\n";

#set special Perl variables for printing
$,="\n";
$|=1;


foreach my $file(@files) {

	#load sequences	
	my $seqs_aref = _get_fasta_sequences($loaddir.$file);# Array ref
	my $rdp_id;

	#look for dups
	my %KseqVid;
	foreach my $line( @$seqs_aref ) {
		if($line =~ />/) {
			$rdp_id = $line;
			next;
		}
		push @{$KseqVid{$line}}, $rdp_id;#$line will be a sequence
	}

	#check if dups found	
	my @duplicates;
	foreach my $ids_aref ( values %KseqVid ) {
		
		#if they contain more than one id then their sequences (keys) in %KseqVid were duplicates,
		if( @$ids_aref > 1 ) {
			push @duplicates, $ids_aref;
		}
	}

	#save a nodupe version of the file
	my $nodupes = $file;
	$nodupes =~ s/fa$/nodupe.fa/;

	open( OUTFILE, ">", $savedir.$nodupes) || die "Can't open file $nodupes\n$!\n";

	foreach my $seq( keys %KseqVid ) {
		print OUTFILE ${$KseqVid{$seq}}[0]."\n";#the first rdp id for any duplicate sequences
		print OUTFILE $seq."\n";
	}

	print "$nodupes\n";
	print "\t(Removed ".(scalar @duplicates)." duplicates in this file)\n" if(@duplicates > 0);
	close OUTFILE;
}

print "\nSaved files to $savedir\n";





#######################
##### subroutines #####
#######################
sub _get_fasta_sequences
{
	my $fafile = shift;
	my $seqio_obj = Bio::SeqIO->new(-file => $fafile, -format => "fasta" );
	my $seq_obj;
	my @SEqs;
	while( my $seq_obj = $seqio_obj->next_seq() ) {
		push @SEqs, (">".$seq_obj->primary_id(), $seq_obj->seq);
	}
	return \@SEqs; 
}



sub _get_filenames
{
	my $dir = shift;
	opendir(IMD, $dir) || die("Cannot open directory");
	my @files = readdir(IMD);
	close IMD;
	shift @files;#get rid of "." and ".." files
	shift @files;
	return @files;
}

