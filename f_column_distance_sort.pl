#!/usr/bin/perl
#
# column_distance_sort.pl
#
# This program sorts the column-formated distance matrix values.
# This step substantially speeds up creation of the .fn.list files
# that MOTHUR produces.
#
# Usage: perl column_distance_sort.pl
#
#

use strict;
use Cwd;
use Config::Tiny;


my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'probeset.conf' );
my $currentdir = getcwd;
my $loaddir = $currentdir."/".$Config->{column_distance}->{savedir}."/";
my $savedir = $loaddir;
my $delunsorted = $Config->{column_distance_sort}->{delete_unsorted_original};
unless( -d $loaddir ) {
	die "Error: specified directory ($loaddir) for distance matrix files does not exist.\n$!\n";
}


print "Loading files from $loaddir\n";

#get filenames
my @files = _get_filenames($loaddir);
@files = grep { /\.dm$/ } sort @files;

if( scalar @files == 0 ) { die "No files to sort.\nSort operates on .dm files in the directory $loaddir\n"; }

print "Loaded ".(scalar @files)." files\n";

#create a temporary directory
my $tmpdir = $currentdir."/pdtmp";
mkdir $tmpdir || die "Error: unable to create directory $tmpdir!\n$!\n";


foreach my $file(@files) {
	
	my $sortedfile=$file;
	$sortedfile =~ s/\.dm/\.sorted/;

	# linux sort command, with alternate temp directory to prevent out of memory error:
	# sort -T pathToSomeOtherDirectory -n -k +3 distFileName -o outfileName
	# +3 specifies sorting on 3rd column (distances)
	my $command = "sort -T $currentdir/tmp -n -k +3 $loaddir$file -o $savedir$sortedfile";
	print "$file...";
	system $command;
	
	#sleep 1;#allow complete writing of file
	
	#make sure the new sorted file exists and is the same size as the original
	my $sizeori=0; my $sizenew=1;#set to unequal initial values
	if( -e $savedir.$sortedfile) {
		$sizeori = -s $loaddir.$file;
		$sizenew = -s $savedir.$sortedfile;
	}
	if($sizeori == $sizenew) {
		print "sorted and saved ok";
		if($delunsorted =~ /t/i) {
			print ". deleting original, unsorted file";
			unlink $loaddir.$file;
		}
		print "\n";
	}
	else {
		print "WARNING: sorted and unsorted file sizes are NOT equal.\n";
	}
}

#delete temporary directory
system "rm -rf pdtmp";

print "\nSaved files to $savedir\n";

exit;






#######################
##### subroutines #####
#######################
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



