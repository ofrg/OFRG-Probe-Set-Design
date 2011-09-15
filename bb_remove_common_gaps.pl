#!/usr/bin/perl

# remove_common_gaps.pl
#
# Running this program is optional but will speed up the creation of distance matrices.
# Run it after remove_variable_regions.pl
#
# This program loads aligned fasta sequences and checks to see if gaps exists in all sequences.
# If any are found, they are removed and the sequences are rewritten without the gaps.
# Doing this helps speed up the calculation of distance matrices.
# 
# The output sequences of this program is used to calculate the distance between them with
# the rdp_column_distance.pl program.
#
# Usage: perl remove_common_gaps.pl
#
use strict;
use Cwd;
use Bio::SeqIO;
use Config::Tiny;


my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'probeset.conf' );
my $currentdir = getcwd;
my $loaddir = $currentdir."/".$Config->{remove_variable_regions}->{savedir}."/";
my $savedir = $currentdir."/".$Config->{remove_variable_regions}->{savedir}."/";
unless( -d $loaddir ) {
        die "Error: specified directory for masked fasta files does not exist.\n$!\n";
}
unless( -d $savedir ) {
        #mkdir $savedir || die "Error: unable to create directory $savedir!\n$!\n";
}
$,="\n";
$|=1;

print "Loading files from $loaddir\n";

#get filenames
my @files = _get_filenames( $loaddir );
@files = grep { /nodupe\.fa$/ } sort @files;


#@files = @files[0..100];#debug

foreach my $file(@files) {

	my $Seqs = _get_sequences($loaddir.$file);# Array ref
	next unless $Seqs;

	print (scalar @$Seqs / 2);
	print "\t";

	my $len = length($$Seqs[1]);
	#my $chars_nodupe = () = $$Seqs[1] =~ /\w/g;###debug

	my @gapcols;

	#determine which columns contain only gaps
	for(my $col=0; $col<$len; $col++) {
		my $onlygaps=1;#default is true
		for(my $seq=1; $seq<@$Seqs; $seq+=2) {
			if(substr($$Seqs[$seq], $col, 1) ne "-") {
				$onlygaps=0;
				last;#don't check others if even one char is not a gap
			}
		}
		push @gapcols, $col if $onlygaps;
	}

	print scalar @gapcols; 
	print "\t".$file."\n";

	#remove gaps
	@gapcols = reverse @gapcols;
	foreach my $col(@gapcols) {
		for(my $seq=1; $seq<@$Seqs; $seq+=2) {
			substr($$Seqs[$seq], $col, 1, "");
		}
	}

	#my $chars_lessgap = () = $$Seqs[1] =~ /\w/g;###debug
	#print "before: ".$chars_nodupe."\tafter: ".$chars_lessgap."\n"; next;###debug

	#save
	$file =~ s/nodupe/lessgap/;
	open(NOCOMMONGAP, ">".$savedir.$file) || die "Can't open $file!\n";
	print NOCOMMONGAP @$Seqs;
	close NOCOMMONGAP;
}



exit;





#######################
##### subroutines #####
#######################
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


sub _get_sequences
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
        return \@SEqs;
}

