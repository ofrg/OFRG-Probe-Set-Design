#!/usr/bin/perl

# remove_variable_regions.pl
#
# This program loads all sequences in a fasta file (including the RDP mask at the begining)
# and removes variable regions in all the sequences.  Next, it truncates the 5' and 3' ends
# and keeps (only) those sequences which do not have more gaps "inward" of the truncation
# point. Further, it checks the remaining DNA sequence for the presence of ambiguous bases and
# discards those that have any. Gaps are NOT removed. All sequences left over are then saved
# in per genera files; multi-part files (ending in AA, AB, etc.)  are concatenated into one file.
#
# The output sequences of this program is used to calculate the distance between them with
# the rdp_column_distance.pl program.
#
# Usage: perl remove_variable_regions.pl
#

 

use strict;
use Cwd;
use Bio::SeqIO;
use Config::Tiny;



my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'probeset.conf' );
my $currentdir = getcwd;
my $loaddir = $currentdir."/".$Config->{remove_variable_regions}->{loaddir}."/";
my $savedir = $currentdir."/".$Config->{remove_variable_regions}->{savedir}."/";
unless( -d $loaddir ) {
	die "Error: specified directory for masked fasta files does not exist.\n$!\n";
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



#remove variable regions
foreach my $file( @files ) {

	my ($part) = $file =~ /-(\w\w)/;# AA,AB,AC, etc.

	#properly handle multi-part files, putting all parts into one output file
	#or starting a new file that has multiple parts
	if( defined $part && $part =~ /AA/ ) {
		
		close FILE if( fileno FILE );#close previous file if open
		my $combinedfilename = $file;
		$combinedfilename =~ s/-$part//;
		open( FILE, ">".$savedir.$combinedfilename ) || die "Error: the file $combinedfilename cannot be opened!\n$!\n";
	}
	elsif( ! defined $part ) {
		
		close FILE if( fileno FILE );
		open( FILE, ">".$savedir.$file ) || die "Error: the file $file cannot be opened!\n$!\n";
	}
	print $file."\n";

	my $Seqs = _get_all_sequences($loaddir.$file);# Array ref

	if( $Seqs ) {
		
		$Seqs = _remove_variable_regions( $Seqs );
		
		for( my $i=0; $i<@$Seqs; $i+=2) {
			
			my $s = $$Seqs[$i+1];

			#get 5' and 3' end sequences up to one base past truncation point
			my ($l) = $s =~ /^(.{38})/;
			my ($r) = $s =~ /(.{142})$/;

			#see if these ends have any nucleotides
			my $b5 = $l =~ /[ACTG]/ ? 1:0;
			my $b3 = $r =~ /[ACTG]/ ? 1:0;
			
			#if both do then save
			if( $b5 && $b3 ) {
				
				#truncate and check remaining sequence for ambiguous bases
				$s =~ s/^.{37}//;
				$s =~ s/.{141}$//;
				
				#check for the presence of ambiguous bases
				my $poorquality = 0;
				my @ambiguousbases = $s =~ /[MRWSYKHDVBN]/g;
				$poorquality = 1 if( @ambiguousbases > 0);
				print FILE $$Seqs[$i]."\n".$s."\n" unless( $poorquality );
			}
		}
	}
}

close FILE;
print "\nSaved files to $savedir\n";

exit;






#######################
##### subroutines #####
#######################
sub _remove_variable_regions
{
	my ( $Seqs ) = shift;
	shift @$Seqs;
	my $mask = shift @$Seqs;
	shift @$Seqs; shift @$Seqs;#get rid of struct name and sequence

	my @zpos;# start positions of zeros in mask
	push @zpos, 0 if(substr( $mask, 0, 1 ) eq "0" );#pos of first zero if mask starts with a zero

	#collect positions in mask where zeros start
	while( $mask =~ /10/g )
	{
		push @zpos, pos($mask)-1;
	}
	@zpos = reverse @zpos;#we will remove these last to first so the positions the substr function uses are not changed

	my @zeros = split(/1+/, $mask);#this puts the zero sections into an array for determining their lengths
	shift @zeros if( $zeros[0] eq "" );#sometimes there's nothing in the first element

	my @zlens = reverse( map { length $_ } @zeros );#calculate lengths, reverse and store

	#now take start positions and lengths to remove masked regions from the sequences
	for( my $i=1; $i<@$Seqs; $i+=2)
	{
		foreach( 0 .. $#zpos )
		{
			substr( $$Seqs[$i], $zpos[$_], $zlens[$_], "" );
		}
	}
	return $Seqs;
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


sub _get_all_sequences
{
	my $fafile = shift;
	my $seqio_obj = Bio::SeqIO->new(-file => $fafile, -format => "fasta" );
	my $seq_obj;
	my @SEqs;
	my $c=0;
	while( my $seq_obj = $seqio_obj->next_seq() )
	{
		push @SEqs, (">".$seq_obj->primary_id(), $seq_obj->seq);
		$c++;
	}
	return 0 unless( $c > 2 );	# every file should contain a mask and struct seqs, so there must
	return \@SEqs;			# be more than two for any actual dna seqs to be there 
}

