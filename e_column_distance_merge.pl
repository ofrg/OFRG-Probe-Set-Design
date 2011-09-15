#!/usr/bin/perl
#
# column_distance_merge.pl
#
# If a large distance matrix is created in two or more parts (using column_distance.pl)
# this program will concatenate them into a single file, and optionally delete the
# partial distance matrix files
#
# Usage: perl column_distance_merge.pl
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

#set special Perl variables for printing
$,="";

print "Loading file(s) from $loaddir\n";

#get all .dmparts filenames
my @files = _get_filenames($loaddir);
@files = grep { /\.dmpart$/ } sort @files;
die "No files to merge in $loaddir\n" if(scalar @files == 0);


my $prevsavefile="";
my $totpartssizes=0;
my $mergedsize;
my $filetoload;
my $savefile;
my @contents;

#foreach my $filetoload(@files) {
for(my $i=0; $i<=@files; $i++) {
	
	if($i < @files) {
		$filetoload = $files[$i];
		$savefile = $filetoload;
		$savefile =~ s/--.*/\.dm/;

		#load contents of $filetoload
		open(INFILE, "<".$loaddir.$filetoload) || die "Can't open file $filetoload\n$!\n";
		@contents = <INFILE>;#slurp
		close INFILE;
	}
	else {
		$savefile = "last";
	}

	#case 1 a new file is started
	#case 2 continuing with a file
	if($savefile ne $prevsavefile) {
		#close previous file if one is opened
		if( fileno OUTFILE ){
			print "closing OUTFILE\n";
			close OUTFILE;
		}
		print $loaddir.$prevsavefile."\n";
		$mergedsize = -s $loaddir.$prevsavefile;
		print "\$mergedsize = $mergedsize ";

		if($mergedsize != $totpartssizes) {
			print "Merged file size does not match total size of all partials for $prevsavefile\n";
		}
		else {
			print "okay to delete part\n";
			_delete_part_files($prevsavefile) if($delpartials =~ /t/i);
		}
		$totpartssizes = 0;
		$prevsavefile = $savefile;
		print $savefile."*\n";
		#open a new file
		unless($savefile eq "last") {
			print "open OUTFILE\n";
			open( OUTFILE, ">".$savedir.$savefile ) || die "Error: the file $savefile cannot be opened!\n$!\n";
		}
	}
	
	unless( $savefile eq "last") {
		$totpartssizes += -s $loaddir.$filetoload;
		print "\$totpartssizes=$totpartssizes $filetoload\n";
		print OUTFILE @contents;
	}

}

print "\nSaved files to $savedir\n";

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
		#unlink $loaddir.$f;
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
