#!/usr/bin/perl
#
# makenamefiles.pl
#
# This program creates a "namefile," necessary for loading column-formatted distance
# matrices into MOTHUR
#

use strict;
use Cwd;
use Bio::SeqIO;
use Config::Tiny;


my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'probeset.conf' );
my $currentdir = getcwd;
my $loaddir = $currentdir."/".$Config->{column_distance}->{savedir}."/";
my $savedir = $currentdir."/".$Config->{column_distance}->{savedir}."/";
unless( -d $loaddir ) {
	die "Error: specified directory for masked fasta files does not exist.\n$!\n";
}
unless( -d $savedir ) {
	mkdir $savedir || die "Error: unable to create directory $savedir!\n$!\n";
}


#get filenames
my @files = _get_filenames($loaddir);
@files = grep { /\.sorted$/ } sort @files;


#set special Perl variables for printing
$,="\n";
$|=1;
 

print "Loading .sorted distance matrix files from $loaddir\n";
print "Loaded ".(scalar @files)." files\n";


foreach my $file( @files ) {

	my %rdpids;

	open( FILE, "<".$loaddir.$file ) || die "Can't open the file, $file !\n$!\n";

	#get RDP IDs by creating hash keys with all of them
	while( my $line = <FILE> ) {
		my ($id1, $id2, $dist) = split( "\t", $line);
		$rdpids{$id1}=1;
		$rdpids{$id2}=1;
	}
	close FILE;

	#make appropriate filename
	$file =~ s/\.sorted$/\.nm/;
	print $file."\n";

	open( OFILE, ">".$savedir.$file ) || die "Can't open the file, $file !\n$!\n";
	my @ids = sort keys %rdpids;

	foreach( @ids ) {
		print OFILE $_."\t".$_."\n";
	}
	close OFILE;

}

print "\nSaved files to $savedir\n";
print "Finished. BEFORE MAKING OTUs, PLEASE ENSURE A COPY OF THE MOTHUR EXECUTABLE IS IN\nTHE DIRECTORY: $savedir\n";

exit;



#######################
##### subroutines #####
#######################

sub _get_filenames {
    my $dir = shift;
    opendir(IMD, $dir) || die("Cannot open directory $dir!\n$!\n");
    my @files = readdir(IMD);
    shift @files;#get rid of "." and ".." files
    shift @files;
    close IMD;
    return @files;
}

