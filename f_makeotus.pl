#!/usr/bin/perl
#
# makeotus.pl
#
# This program runs MOTHUR on multiple column-formated distance matrices,
# and calls MOTHUR's hcluster() command to create OTUs (saved as .list files).
# the .list files are moved to another directory and the .sabund and .rabund
# files are deleted.
#
#
# Usage: perl makeotus.pl
#
# Usage for individual files:  perl makeotus.pl <sorted distance matrix file>
#


use strict;
use Cwd;
use Bio::SeqIO;
use Config::Tiny;


my $largestsfile="large_files_skiped_by_mothur.txt";#file to contain the names of large files


my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'probeset.conf' );
my $currentdir = getcwd;
my $loaddir = $currentdir."/".$Config->{column_distance}->{savedir}."/";#d_distances
my $savedir = $currentdir."/".$Config->{makeotus}->{savedir}."/";	#f_otu_lists
my $cutoff = $Config->{makeotus}->{cutoff};
my $precision = $Config->{makeotus}->{precision};
my $method = $Config->{makeotus}->{method};
my $minsize = $Config->{makeotus}->{minsize};
my $maxsize = $Config->{makeotus}->{maxsize};
my $skiplarge = $Config->{makeotus}->{skipLargeFiles};
unless( -d $loaddir ) {
	die "Error: specified directory for masked fasta files does not exist.\n$!\n";
}
unless( -d $savedir ) {
	mkdir $savedir || die "Error: unable to create directory $savedir!\n$!\n";
}


#command line options. used for largest files
#$dothisfileonly=name of a single file to process
my ($dothisfileonly) = @ARGV;

#get filenames
my @files = _get_filenames($loaddir);
@files = grep { /\.sorted$/ } sort @files;


#check for .list files already made so we can skip them
my @alreadymadefiles = _get_filenames($savedir);
@alreadymadefiles = grep { /\.list/ } sort @alreadymadefiles;
@alreadymadefiles = grep { s/\.list/\.sorted/ } @alreadymadefiles;


#make and save a list of large files not already made
my @largefiles = grep { (-s $loaddir.$_) > $maxsize } @files;
my @temp;
foreach my $f( @largefiles ) {
	push @temp, $f unless( grep{ /$f/ } @alreadymadefiles );
}
@largefiles = @temp; undef @temp;
@largefiles = map { (-s $loaddir.$_)."\t".$_ } @largefiles;

#save names of large files skipped by this script if necessary
_save_names(\@largefiles,$largestsfile) if(! defined $dothisfileonly && $skiplarge !~ /f/i );


my @filestodo;
foreach my $f( @files ) {
	push @filestodo, $f unless( grep{ /$f/ } @alreadymadefiles );
}

#handle case where user wants to process just one file
if(defined $dothisfileonly) {
	@filestodo=$dothisfileonly;
	$skiplarge="false";
}

print "Loading files from $loaddir\n";
print "Loaded ".(scalar @filestodo)." files\n";

my $mo1 = './mothur "#hcluster(column=';
my $mo2 = ', name=';
my $mo3 = ', cutoff=';
my $mo4 = ', precision=';
my $mo5 = ', method=';
my $mo6 = ', sorted=t)"';

#mothur has to be run in the same directory as the distance matrices
chdir $loaddir;
die "Error: the mothur program does not appear to be in the distance matrix directory $loaddir\n" 
	unless(-e "mothur");

my $startime = time();

#@filestodo=@filestodo[0..10];#debug
foreach my $sortfile( @filestodo ) {
	unless($sortfile =~ /\.sorted$/) {
		print "$sortfile is not a .sorted distance matrix file\n" ;
		next;
	}
	
	my $s = -s $loaddir.$sortfile;

	#skips large files if user designated to do so and files with only one distance (too small)
	next if( ($s > $maxsize && $skiplarge =~ /t/i) || $s <= $minsize );

	my $nmfile = $sortfile;
	$nmfile =~ s/\.sorted/\.nm/;

	my $command = $mo1.$sortfile.$mo2.$nmfile.$mo3.$cutoff.$mo4.$precision.$mo5.$method.$mo6;

	print $command."\n";

	system $command;
	

	#create MOTHUR's .fn.list output filename so we can "see" when it's been made
	#(there can be a lag where perl gets control back but the file isn't visible yet)
	my $listfile = $sortfile;
	unless($listfile =~ s/\.sorted/\.fn\.list/) {
		die "Error: unable to create .list filename for $sortfile\n";
	}
	#wait until it has been made
	while( ! -e $listfile ) {
		sleep 1;
	}

	#escape any space chars in the name so UNIX mv (move) command doesn't choke
	$listfile =~ s/\s/\\ /g;

	#then move it to the save directory
	system "mv -f $listfile $savedir";

	#and delete the other two (uneeded) files created by MOTHUR
	system "rm -f *.fn.[rs]abund";

}

my $donetime = time();
my $tottime = $donetime - $startime;
print "Elapsed time: ".$tottime." seconds\n";
print "Large distance matrix files have not yet been processed as ".
			"you have elected to skip them.\nTheir names can be found in the ".
			"file \"$largestsfile\".\n" if($skiplarge =~ /t/ig);

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



sub _save_names 
{
	my ($names_aref, $file) = @_;
	open(FILE, ">".$file) || die "Error: the file $file cannot be opened!\n$!\n";
	$,="\n";
	print FILE @$names_aref;
	print FILE "\n";
	close FILE;
}
