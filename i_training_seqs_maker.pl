#!/usr/bin/perl
#
# training_seqs_maker.pl
#
# This program creates the training sequences for probe set design.
#
# First it removes variable regions in all the sequences.  then it truncates the 5' and 3' ends
# and keeps (only) those sequences which do not have more gaps immediately "inward" of the truncation
# point (i.e., the sequence must be a minimum size to be kept). next, it checks the remaining DNA
# sequence for the presence of ambiguous bases and discards those that have them.
# Before saving the sequence it figures out to which OTU the sequence belongs with the OTU
# information it has loaded from MOTHUR generated .list files, then saves all this information together.
#
# Usage: perl training_seqs_maker.pl
#

use strict;
use Cwd;
use Bio::SeqIO;
use Config::Tiny;


my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'probeset.conf' );
my $currentdir = getcwd;
my $fastadir = $currentdir."/".$Config->{remove_variable_regions}->{loaddir}."/";
my $otusdir = $currentdir."/".$Config->{makeotus}->{savedir}."/";

my $savedir = $currentdir."/".$Config->{training_seqs_maker}->{savedir}."/";
my $savetrainfile = $Config->{training_seqs_maker}->{savetrainfile};
my $savealignfile = $Config->{training_seqs_maker}->{savealignfile};

my $trainSeqsDistCutoff = $Config->{training_seqs_maker}->{cutoff};
my $cutoffmade = $Config->{makeotus}->{cutoff};#to compare with this script's cutoff

unless( -d $fastadir ) {
	die "Error: specified directory for masked fasta files does not exist.\n$!\n";
}
unless( -d $otusdir ) {
	die "Error: specified directory for .list files does not exist.\n$!\n";
}
unless( -d $savedir ) {
	mkdir $savedir || die "Error: unable to create save directory $savedir!\n$!\n";
}
unless($trainSeqsDistCutoff <= $cutoffmade) {
	die "Error: cutoff distance to make OTUs is greater than what is available in .list files.";
}


#get filenames
my @files = _get_filenames( $fastadir );
@files = sort @files;
@files = grep { /\.fa$/ } @files;

#set special Perl variables for printing
$,="\n";
$|=1;


print "Loading fasta files from $fastadir\n";		# maskedfastas/
print "Loading .list OTU files from $otusdir\n";# otu_lists/
print "Loaded ".(scalar @files)." fasta files\n";


open( TRAINOUTFILE, ">".$savedir.$savetrainfile."_c_".$trainSeqsDistCutoff ) || die "Can't open $savedir.$savetrainfile\n$!\n";
open( ALIGNOUTFILE, ">".$savedir.$savealignfile."_c_".$trainSeqsDistCutoff ) || die "Can't open $savedir.$savealignfile\n$!\n";

my $otunum=0;
my %phyla;
my %genera;

foreach my $file( @files ) {

	my $seq_href;
	
	#get part designation if it has one
	my ($part) = $file =~ /(-\w\w)/;

	if( defined $part && $part !~ /-AA/ ) {
		next;
	}
	elsif( defined $part && $part =~ /-AA/ ) {
		my $regex = $file;
		$regex =~ s/$part/-\.\./;
		my @sames = grep { /$regex/ } @files;
		foreach my $f( @sames ) {
			my $sqs_aref = _get_all_sequences($fastadir.$f);
			$seq_href = _remove_variable_regions( $sqs_aref, $seq_href );
		}
		$file =~ s/$part//;
	}
	else {
		my $sqs_aref = _get_all_sequences($fastadir.$file);
		$seq_href = _remove_variable_regions( $sqs_aref, $seq_href );
	}

	#print $file."\n";

	#get taxa from this file's filename
	my ($phy, $gen) = $file =~ /Bacteria\.*(.+?)[\._]{1}.*?_(.+?)\.fa$/;
	($phy, $gen) = $file =~ /(Bacteria)_{1}(.+?)\.fa$/ if( ! defined $phy );#a unique case

	#counters to convert names into numbers
	$phyla{$phy}++;
	$genera{$phy.$gen}++;
	my $phynum = scalar keys %phyla;
	my $gennum = scalar values %genera;
	
	#convert filename to corresponding mothur .list name
	my $mothurname = $file;
	$mothurname =~ s/\.fa/\.nodupe\.fn\.list/;
	print $mothurname."\n";
	
	#get OTUs for this genus from the .list file
	my @OTUgroups = _getOTUs( $otusdir.$mothurname, $trainSeqsDistCutoff );
	if( ! @OTUgroups ) {
    	print "File ".$mothurname." contains no OTUs!\n";
	    next;
   }
	
	
	#for each OTU in this genus
	foreach my $otugroup( @OTUgroups ) {
		
		my @rdpids = sort split( ',', $otugroup );			
		die "Error: no RDP IDs found in: otugroup(".$otugroup."). Check $mothurname\n" unless( @rdpids > 0 );
		
		
		foreach my $id( @rdpids ) {
			
			#get sequence for this $id
			my $s = $$seq_href{$id};
			
			#print $phy."\t".$gen."\t".$otunum."\t".$id."\t".$s."\n" if( $s );#debug
			
			if( $s ) {
				my $alignseq = $s;
				
				#training seqs (used for making probes) must NOT contain gaps but MUST contain '#'s to avoid making probes that span a variable region
				$s =~ s/-//g;
				print TRAINOUTFILE $phy."\t".$phynum."\t".$gen."\t".$gennum."\t".$otunum."\t".$id."\t".$s."\n";
				
				#aligned sequences MUST contain gaps so alignment stays true but must NOT contain '#'s which are only markers for training seqs
				$alignseq =~ s/#//g;					
				print ALIGNOUTFILE $phy."\t".$phynum."\t".$gen."\t".$gennum."\t".$otunum."\t".$id."\t".$alignseq."\n";
			}
			else {
				print $id."*not found*";###debug
			}
		}
		$otunum++;
	}
}


close TRAINOUTFILE;
close ALIGNOUTFILE;

print "\nSaved files to $savedir\n";

exit;






#######################
##### subroutines #####
#######################

#get OTUs from MOTHUR created .list files
sub _getOTUs {
	
	my $filename = shift;
	my $trainSeqsDistCutoff = shift;
	my $line; my $prevline; my $keepline;
	unless( open( FILE, "<",$filename ) ) {
		#print, don't die. many .list files do not exist. their .fa files
		#may have only 1 sequence
		$filename =~ s/.*\///;
		print( "$filename\ncould not be opened\n" );
		return 0;
	}
	
	#read file up to the desired cutoff value
	while( <FILE> ) {
		$prevline = $line;
		$line = $_;
		my ($cutoff) = $line =~ /^(.*?)\t/;#capture all text before first tab
		$cutoff =~ s/unique/0/;

		if( $cutoff == $trainSeqsDistCutoff ) {
			$keepline = $line;
			last;
		}
		if( $cutoff > $trainSeqsDistCutoff || eof FILE ) {			
			$keepline = $prevline;
			last;
		}
	}

	close FILE;
	
	if( ! $prevline ) {	
		$keepline = $line;
	}
	if( $keepline ) {
		chomp $keepline;
	}
	
	# $keepline now holds the line in the MOTHUR .list file that we want
	# to extract (grouped) RDP IDs from
	$keepline =~ s/.*\t\d+\t?//;#trim to keep only OTUs
	my @OTUgroups = split( "\t", $keepline );
	return @OTUgroups;#can return a null value but that's okay
}



# compares the sequences with the mask directly each time
sub _remove_variable_regions {

	my ( $Seqs_aref, $KidVseq ) = @_;
	shift @$Seqs_aref;#name of mask not needed
	my $mask = shift @$Seqs_aref;
	shift @$Seqs_aref; shift @$Seqs_aref;#get rid of struct name and sequence - also not needed
	
	#process the mask first
	my @zpos;#holds start positions of zeros in mask
	push @zpos, 0 if(substr( $mask, 0, 1 ) eq "0" );#pos of first zero if mask starts with a zero
	#collect positions in mask where zeros regions start
	while( $mask =~ /10/g ) {
		push @zpos, pos($mask)-1;
	}
	@zpos = reverse @zpos;#working with largest indexes first won't screw up correct positions of smaller ones 
	#put zero sections into an array for determining their lengths
	my @zeros = split(/1+/, $mask);#split on (one or more) 1s
	shift @zeros if( $zeros[0] eq "" );#if mask started with a 1 there will be nothing in the first element
	#calculate lengths, reverse and store
	my @zlens = reverse( map { length $_ } @zeros );
	
	
	#remove variable regions in sequences based on the positions of zeros in the mask#
	#my %KidVseq;
	for( my $i=1; $i<@$Seqs_aref; $i+=2) {
	
		#sequence IDs are first, then the sequences
		# for each zero region starting position:
		foreach( 0 .. $#zpos ) {
			# check the sequence for the presence of any lower-case letters in the same regions where there are zeros in the mask.
			# if lower-case letters are found, replace that region with a '#'. if not found, remove region but add nothing back.
			# (the # prevents probes from being made from that section later on).
			if( substr( $$Seqs_aref[$i], $zpos[$_], $zlens[$_] ) =~ /[a-z]/o ) {
					substr( $$Seqs_aref[$i], $zpos[$_], $zlens[$_] ) = "#";
			}
			else {
				substr( $$Seqs_aref[$i], $zpos[$_], $zlens[$_] ) = "";
			}
		}
		
		$$KidVseq{$$Seqs_aref[$i-1]} = _truncate_ends($$Seqs_aref[$i]);
		
	}

	return \%$KidVseq;
}



# truncate ends 10 bases inwards of the 27F and 1392R universal bacterial primer sites
sub _truncate_ends {
	my $s = shift;
	my $unibac27F_endpoint=27;	#(from nearest end of alignment)
	my $unibac1392R_endpoint=131;	#(from nearest end of alignment)
	my $marginbases=10;
	
	#check 5' end
	my $leftpos=0; my $lchars=0; my $areLeftchars=0;
	while( $lchars<=$unibac27F_endpoint+$marginbases ) {
		
		$lchars++ unless( substr($s, $leftpos, 1) eq "#" );	#count all but '#' chars
		$leftpos++;#but still increment position counter
		$areLeftchars = 1 if( substr($s, $leftpos, 1) !~ /[-#]/ );
	}
	#check 3' end
	my $rightpos=length($s)-1; my $rchars=0; my $areRightchars=0; my $rightposCounter=0;
	while( $rchars<=$unibac1392R_endpoint+$marginbases ) {
		
		$rchars++ unless( substr($s, $rightpos, 1) eq "#" );
		$rightpos--;
		$rightposCounter++;
		$areRightchars = 1 if( substr($s, $rightpos, 1) !~ /[-#]/ );
	}
	
	$rightposCounter--; $leftpos--;#set to actual truncatation positions
	
	$s =~ s/^.{$leftpos}//;		#truncate left side
	$s =~ s/.{$rightposCounter}$//;	#truncate right side
	
	#now check for the presence of ambiguous bases
	my $poorquality = 0;
	my @ambiguousbases = $s =~ /[MRWSYKHDVBN]/og;
	$poorquality = 1 if( @ambiguousbases > 0);
	
	#TODO quality control may not be necessary here, as we should only be using
	#rdp ids from .list files, and these have already been filtered.
	$s = 0 if( ! $areLeftchars || ! $areRightchars || $poorquality );
	return $s;	
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



sub _get_all_sequences {
    my $fafile = shift;
    my $seqio_obj = Bio::SeqIO->new(-file => $fafile, -format => "fasta" );
    my $seq_obj;
    my @SEqs;
    my $c=0;
    while( my $seq_obj = $seqio_obj->next_seq() ) {
        push @SEqs, ($seq_obj->primary_id(), $seq_obj->seq);
        $c++;
    }
    return 0 unless( $c > 2 );	# every file should contain a mask and struct seqs so there must
    return \@SEqs;							# be more than two for any actual dna seqs to be there 
}

