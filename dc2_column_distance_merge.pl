#!/usr/bin/perl
#
# dc2_column_distance_merge.pl
#
# If a large distance matrix is created in two or more parts this program will 
# concatenate them into a single file, and optionally delete the partial 
# distance matrix files.
#
# Usage: perl column_distance_merge.pl
#
#
# This version uses less RAM but has not been well tested. Use with caution!
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
my $delpartials = $Config->{column_distance_merge}->{delete_parts_after_merge};
unless( -d $loaddir ) {
	die "Error: specified directory of masked fasta files does not exist.\n";
}


print "Loading file(s) from $loaddir\n";

#get all .dmparts filenames
my @files = _get_filenames($loaddir);
@files = grep { /\.dmpart$/ } sort @files;
die "No files to merge in $loaddir\n" if(scalar @files == 0);


#get the part names vs the base/save names organized
my %mergednames;
foreach my $file(@files) {
	my $base = $file;
	$base =~ s/--\d\d\.dmpart//g;
	push @{$mergednames{$base}}, $file;
}


#get base names
my @merged = keys %mergednames;


foreach my $basename(@merged) {
	
	my @files = sort @{$mergednames{$basename}};#all files with same base name

	my $savefile = $basename.".dm";
	print $savefile."\n";

	open(OUTFILE, ">".$savedir.$savefile) || die "Can't open file $savefile\n$!\n";


	my $totfilesizes=0;
	foreach my $filetoload( @files ) {
		my $thisfilesize = -s $loaddir.$filetoload;
		$totfilesizes += $thisfilesize;
		print $filetoload." size= $thisfilesize  $totfilesizes\n";

		open(INFILE, "<".$loaddir.$filetoload) || die "Can't open file $filetoload\n$!\n";

		while(my $line = <INFILE>) {
			print OUTFILE $line;
		}
		close INFILE;
	}
	close OUTFILE;
	print $totfilesizes."\n";
}


exit;




#######################
##### subroutines #####
#######################
sub _delete_part_files {
	my $delfile = shift;
	$delfile =~ s/\.dm//;
	my @delfiles = grep { /$delfile/ } @files;
	foreach my $f( @delfiles ) {
		print "Deleting: $f\n";
		unlink $loaddir.$f;
	}
}



sub _get_filenames {
    my $dir = shift;
    opendir(IMD, $dir) || die("Cannot open directory");
    my @files = readdir(IMD);
    shift @files;#get rid of "." and ".." files
    shift @files;
    close IMD;
    return @files;
}
