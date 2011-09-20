#
# rdp_downloader.pl
#
#	this program interacts with the RDP2 website and downloads sequences in
#	fasta format ** by genera **
#
# NOTE: this program MUST use a modified version of Win32::IEAutomation::WinClicker.pm
#       that corrects a bug in it.  First, install Win32::IEAutomation for Perl, then
#				copy the WinClicker.pm version that came with this software into the
#				C:\Perl64\site\lib\Win32\IEAutomation\ directory (or wherever
#				Win32::IEAutomation was installed). It is okay to overwrite the original
#				as this version is compatible with it.
#
#
# Copyright (C) 2011 Paul Ruegger
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.


use strict;
use Cwd;
use Win32::IEAutomation;
use Win32::IEAutomation::WinClicker;
use Config::Tiny;



my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'rdp_downloader.conf' );
my $currentdir = getcwd;
my $savedir = $currentdir."/".$Config->{rdp_downloader}->{savedir}."/";
my $downloadChunkLimit = $Config->{rdp_downloader}->{downloadChunkLimit};#RDP currently limits downloads to 3k sequences (if you want a mask)
my $RDP_user = $Config->{rdp_downloader}->{RDP_username};
my $RDP_pass = $Config->{rdp_downloader}->{RDP_userpassword};
#boolean. T if you want to start from scratch, F to start in the middle somewhere
my $safp = $Config->{rdp_downloader}->{startatfirstphylum};
my $startatfirstphyla = ($safp =~ /t/i) ? 1 : 0;#convert to 0 or 1
#starting phylum & genus if $startatfirstphyla=F. ignored if $startatfirstphyla=T
my $startphyla = $Config->{rdp_downloader}->{startphylum};
my $startgenera = $Config->{rdp_downloader}->{startgenus};
my $RDP_url = $Config->{rdp_downloader}->{RDP_url};
unless( -d $savedir ) {
	mkdir $savedir || die "Error: unable to create directory $savedir.";
}
if($RDP_user eq "" || $RDP_pass eq "") {
	die "Please ensure your RDP username and password have been added to the rdp_downloader.conf file\n";
}


#TODO remove these
#boolean. 1 if you want to download unclassified sequences also
my $downloadunclassified = 0;
#boolean. 1 if you want ONLY unclassified sequences downloaded    
my $unclassifiedonly = 0;



# Create a new instance of Internet Explorer
my $ie = Win32::IEAutomation->new( visible => 1, maximize => 0, warnings => 0 );

$ie->gotoURL($RDP_url);

#login if not already logged in
unless ( $ie->getLink( 'linkurl:', qr/updateAcct/ ) ) {
	$ie->getImage( 'imgurl:', qr/myRDP90x33/ )->Click();
	$ie->getTextBox( 'name:', "j_username" )->SetValue($RDP_user);
	$ie->getTextBox( 'name:', "j_password" )->SetValue($RDP_pass);
	$ie->getButton( 'name:', "login" )->Click();
}

#navigate to Browser page
if ( $ie->getLink( 'linktext:', 'Browsers' ) ) {
	$ie->getLink( 'linktext:', 'Browsers' )->Click();
}


#ensure we "start over" if the page puts us somewhere we've previously been
if ( $ie->getButton( 'name:', 'browse' ) ) {
	$ie->getButton( 'name:', 'browse' )->Click();
}
else {
	$ie->getLink( 'linkurl:', qr/hb_intro.jsp/ )->Click();
	$ie->getButton( 'name:', 'browse' )->Click();
}

#sometimes necessary if restarting a session
_unselect_sequences($ie);


$ie->getSelectList( 'name:', 'depth' )->SelectItem('3');# if( $unclassifiedonly );

my @phypage = $ie->PageText();

#parse out phylum names. ignore those with no sequences
my @phyla = grep ( s/\s*?phylum // && !/(0\/0\/0)/, @phypage );
@phyla = grep( s/\(.*\)//, @phyla );
@phyla = grep( s/\s*$//,   @phyla );
my @phyunclas = grep( /\s*(unclassified\w*?)/ && !/(0\/0\/0)/, @phypage );
@phyunclas = grep( s/\(.*\)//,   @phyunclas );
@phyunclas = grep( s/\s*$//,     @phyunclas );
@phyunclas = grep( s/\s{2,}?//g, @phyunclas );
@phyunclas = grep( !/Root/,      @phyunclas );
@phyunclas = grep( !/Archaea/,   @phyunclas );

#push @phyla, @phyunclas if( $unclassifiedonly );
#@phyla = @phyunclas if( $unclassifiedonly );

#allows starting at an internal phylum instead of the first
if ( !$startatfirstphyla ) {
	my $c           = 0;
	my $lastelement = $#phyla;
	foreach (@phyla) {
		if ( $_ =~ /$startphyla/ ) {

			#slice away elements up to the desired phyla
			@phyla = @phyla[ $c .. $lastelement ];
			last;
		}
		$c++;
	}
}


#cycle through phyla, getting genera within
foreach my $phyla (@phyla) {

	next unless ($phyla);

	print "Current Phylum: $phyla\n";

	#my $url = $ie->getLink('linktext:',"Root")->linkUrl();

	#click the phyla link
	$ie->getLink( 'linktext:', $phyla )->Click;

	#make the depth 10, ensuring all genera are visible
	$ie->getSelectList( 'name:', 'depth' )->SelectItem('10');

	#get all genera names on current page
	my @page = $ie->PageText();

	#if ( $phyla =~ /unclassified/ ) {
		#my @text = grep( /$phyla/, @page );
		#my $text = shift @text if( @text );
		#my ($n) = $text =~ /unclassified.+?\/(\d+)\//;#grab the number of seqs
		#_download_unclassified_masked_fasta( $ie, $phyla, $n );
		#_unselect_all_sequences( $ie, $phyla );
	#	next;
	#}

	my @genera = grep( s/\s*?genus // && !/(0\/0\/0)/, @page );
	@genera = grep( s/\s*$//, @genera );

	my @allunclassified = grep( /(unclassified\w*?)/ && !/(0\/0\/0)/, @page );
	@allunclassified = grep( s/\s*?u/u/, @allunclassified );

	push @genera, @allunclassified if ($downloadunclassified);
	@genera = @allunclassified if ($unclassifiedonly); #used for mopping up only unclassified organisms. change array to get specific taxonomic levels
	
	
	#this code allows starting at an internal genus instead of the very first
	if ( !$startatfirstphyla ) {
		if ( $phyla =~ /$startphyla/ ) {
			my $c = 0;
			foreach (@genera) {
				if ( $_ =~ /$startgenera/ ) {
					#slice away elements up to the desired genus
					@genera = @genera[ $c .. $#genera ];
					last;
				}
				$c++;
			}
		}
	}

	#if @genera is empty, reset webpage and get next phyla
	unless (@genera) {
		_goto_phylum_page($ie);
		next;
	}

	#now fetch masked fasta files
	foreach my $generainfo (@genera) {
		my ($genus)        = $generainfo =~ /^(.*?)\s+?\(/;
		my ($numsequences) = $generainfo =~ /\/(\d+)\//;

		next unless ($genus);

		print "\t\t$phyla:\tGenus: $genus\t";

		if ( $numsequences <= $downloadChunkLimit ) {

			unless ( _select_all_sequences( $ie, $genus ) ) { next; }
			_download_masked_fasta( $ie, $genus, $numsequences );
			$ie->WaitforDone();
			_unselect_all_sequences( $ie, $phyla );
			$ie->WaitforDone();
		}
		else {

			print "\tGenus:".$genus." contains > $downloadChunkLimit sequences.\n";
			_download_large_genera_masked_fasta( $ie, $genus, $numsequences );
			$ie->WaitforDone();
			_reset_page_to_phyla_level( $ie, $phyla);
			$ie->WaitforDone();
		}
		print "";

	}

	_goto_phylum_page($ie);
	$ie->WaitforDone();

	sleep 1;

}

exit;






#################################
######### subroutines ###########
#################################
sub _reset_page_to_phyla_level {
	my ( $ie, $phyla ) = @_;
	if ( $ie->getLink( 'linkurl:', qr/hb_intro.jsp/ ) ) {
		$ie->getLink( 'linkurl:', qr/hb_intro.jsp/ )->Click();
	}
	if ( $ie->getButton( 'name:', 'browse' ) ) {
		$ie->getButton( 'name:', 'browse' )->Click();
	}
	$ie->getLink( 'linktext:', $phyla )->Click;
	$ie->getSelectList( 'name:', 'depth' )->SelectItem('10');
}



sub _unselect_all_sequences {
	my ( $ie, $phyla ) = @_;
	
	$ie->WaitforDone();
	
	if ( $ie->getImage( 'imgurl:', qr/images\/diag.gif/ ) ) {
		$ie->getImage( 'imgurl:', qr/images\/diag.gif/ )->Click();
	}
	$ie->WaitforDone();
	if ( $ie->getImage( 'imgurl:', qr/images\/plus.gif/ ) ) {
		$ie->getImage( 'imgurl:', qr/images\/plus.gif/ )->Click();
	}
	$ie->WaitforDone();
	if ( $ie->getImage( 'imgurl:', qr/images\/minus.gif/ ) ) {
		$ie->getImage( 'imgurl:', qr/images\/minus.gif/ )->Click();
	}
	$ie->WaitforDone();
}



sub _unselect_sequences {
	my $ie = shift;

	$ie->WaitforDone();
	
	#unselect sequences
	if ( $ie->getImage( 'imgurl:', qr/images\/diag.gif/ ) ) {
		$ie->getImage( 'imgurl:', qr/images\/diag.gif/ )->Click();
	}
	$ie->WaitforDone();
	if ( $ie->getImage( 'imgurl:', qr/images\/minus.gif/ ) ) {
		$ie->getImage( 'imgurl:', qr/images\/minus.gif/ )->Click();
	}
	$ie->WaitforDone();
}



sub _download_large_genera_masked_fasta {
	my ( $ie, $genus, $n ) = @_;
	$ie->WaitforDone();
	if ( $ie->getLink( 'linktext:', $genus ) ) {
		$ie->getLink( 'linktext:', $genus )->Click();
		$ie->WaitforDone();
	}
	else {
		print "Can't follow the $genus link\n";
		return 0;
	}

	#get the currentRoot value. necessary for quickly skipping
	#many already-downloaded sequences.
	my $url = $ie->getLink( 'linktext:', "Root" )->linkUrl();
	my ($currentRoot) = $url =~ /currentRoot=(\d+)/;

	__download_large_block_of_seqs( $ie, $genus, $n, $currentRoot );
	$ie->WaitforDone();
}



sub _download_unclassified_masked_fasta {
	my ( $ie, $taxa, $n ) = @_;
	my $url = $ie->getLink( 'linktext:', "Root" )->linkUrl();
	my ($currentRoot) = $url =~ /currentRoot=([-]\d+)/;
	__download_large_block_of_seqs( $ie, $taxa, $n, $currentRoot );
}



sub __download_large_block_of_seqs {
	my ( $ie, $genus, $n, $currentRoot ) = @_;
	
	my $urla = 'http://rdp.cme.msu.edu/hierarchy/hierarchy_browser.jsp?qvector=204&depth=10&openNode=0&seqid=&currentRoot=';
	my $urlb = '&searchStr=&endDataValue=';
	my $urlc = '&showOpt=';
	
	$genus =~ s|/||g;#for genus "Escheveria/Shigella", which can't save correctly
	my $fulltaxa = _get_full_taxaname($ie);
	
	my $seqsleft = $n;
	#$downloadChunkLimit is current maximum of fasta seqs RDP will let you download with mask
	my $p  = $n / $downloadChunkLimit;

	# bool ? (val if true) : (val if false)
	my $portions_to_download = ( $p == int($p) ) ? $p - 1 : int($p);
	my @letters = split( '', "ABCDEFGHIJKLMNOPQRSTUVWXYZ" );
	
	#how many times do we need the alphabet for filename endings?
	my $alphabets = int($p / (scalar @letters));
	my @endings;
	for(my $i=0; $i<=$alphabets; $i++) {
		my @newendings = map { $letters[$i].$_ } @letters;
		push @endings, @newendings;#AA to AZ, BA to BZ, CA to CZ, etc.
	}
		
	
	foreach my $portionnum ( 0 .. $portions_to_download ) {
		
		#tack on a double-letter ending, designating which part this is
		my $portion = "-". $endings[$portionnum];
		my $filename = $fulltaxa . "__" . $genus . $portion;
		$filename =~ s/"//g;

		#get $downloadChunkLimit seqs or balance of seqs left
		my $seqs_left_to_get_this_portion = ( $seqsleft > $downloadChunkLimit ) ? $downloadChunkLimit	: $seqsleft;
		my $seqs_to_save_this_portion = $seqs_left_to_get_this_portion;
		$seqsleft = $seqsleft - $seqs_left_to_get_this_portion;
		
		while ( $seqs_left_to_get_this_portion > 0 ) {
			
			$ie->WaitforDone();
			my @page       = $ie->PageText();
			$ie->WaitforDone();
			my @seqs       = grep ( /S\d{9} /, @page );
			my $seqsonpage = scalar @seqs;
			
			#click the checkboxes on current page
			foreach my $idx ( 1 .. $seqsonpage ) {
				$ie->getCheckbox( 'index:', $idx )->Select();
				$seqs_left_to_get_this_portion--;
				$ie->WaitforDone();
			}
			
			#need to do this to "lock" the checkbox clicks in place
			if ( $ie->getLink( 'linktext:', "Next" ) ) {
				$ie->getLink( 'linktext:', "Next" )->Click;
			}
			else {
				$ie->getLink( 'linktext:', "Prev" )->Click;
			}
		}
		
		#sequences should be selected now, so download them
		_download_seqs( $ie, $filename, $seqs_to_save_this_portion );
		$ie->WaitforDone();
		$ie->Back();
		$ie->WaitforDone();
		
		_unselect_sequences($ie);
		$ie->WaitforDone();
		
		#reset to correct page if there are more sequences left to download
		if ( $seqsleft > 0 ) {
			my $datavalue = ( $portionnum + 1 ) * $downloadChunkLimit;
			$ie->gotoURL( $urla . $currentRoot . $urlb . $datavalue . $urlc );
			$ie->WaitforDone();
		}
	}
}



sub _download_seqs {
	my ( $ie, $genus, $n ) = @_;

	$ie->getLink( 'linkurl:', qr/dload.spr/ )->Click();
	$ie->getRadio( 'id:', "rdpId" )->Click();
	$ie->getRadio( 'id:', "showMask" )->Click();

	if ( $ie->getButton( 'value:', qr/Download $n/ ) ) {
		$ie->getButton( 'value:', qr/Download $n/ )->Click();
		$ie->WaitforDone();
	}
	else {
		die "Button text doesn't match number of sequences selected ($n $genus).\n";
		#print "Button text doesn't match number of sequences selected ($n $genus).\n";
	}

	#make a correctly formatted filename for saving
	my $perlfilename = $savedir.$genus.".fa";
	$perlfilename =~ s/"//g;
	my $dialogfilename = $perlfilename;
	$dialogfilename =~ s|/|\\|g;

	#delete if it already exists (or it asks for  
	#confirmation to overwrite and messes everything up)
	if ( -e $perlfilename ) {
		unlink $perlfilename;
	}

	
	my $clicker = Win32::IEAutomation::WinClicker->new();
	$clicker->push_save_button( "File Download", 120 );
	$ie->WaitforDone();
	$clicker->push_save_button( "File Download", 1 );#don't convince yourself this doesn't need to be here
	$clicker->send_text( "Save As", '{BACKSPACE}', 120 );
	$ie->WaitforDone();
	
	#AutoIt can only handle strings 127 chars long
	my $length = length($dialogfilename);
	if ( $length > 127 ) {
		my $restofit        = $length - 127;
		my $dialogfilename1 = substr( $dialogfilename, 0, 127 );
		my $dialogfilename2 = substr( $dialogfilename, 127, $restofit );
		$clicker->send_text( "Save As", $dialogfilename1 );
		$clicker->send_text( "Save As", $dialogfilename2 );
	}
	else {
		$clicker->send_text( "Save As", $dialogfilename );
	}
	$ie->WaitforDone();
	$clicker->push_save_button( "Save As", 60 );
	$ie->WaitforDone();
	#$clicker->WinActivate("Internet");
}



sub _goto_phylum_page {
	my $ie   = shift;
	my $page = $ie->PageText();
	while ( $page !~ /no rank/ ) {
		$ie->Back();
		sleep 1;
		$page = $ie->PageText();
	}
	$ie->getSelectList( 'name:', 'depth' )->SelectItem('3');
}



sub _get_full_taxaname {
	my ($ie) = @_;
	my @page = $ie->PageText();
	my @taxa = grep ( /Root/, @page );
	my $t = shift @taxa;
	$t =~ s/\(\d+\/\d+\/\d+\)//g;    #get rid of parentheses with numbers
	$t =~ s/\s+//g;
	$t =~ s/"//g;  #occassionally names are quoted, which is a bad thing for filenames
	my @temp = split( ";", $t );
	shift @temp;    #gets rid of "Root" name
	return ( join( ".", @temp ) );
}



sub _download_masked_fasta {
	my ( $ie, $genus, $n ) = @_;
	my $fulltaxa = _get_full_taxaname($ie);
	$genus = $fulltaxa . "__" . $genus;
	_download_seqs( $ie, $genus, $n );
	$ie->Back();
	$ie->Back();    #to sequence selection page
}



#sub _download_distance_matrix {
#	my ( $ie, $genus, $numsequences ) = @_;
#	my $time = int( $numsequences / 150 );
#	$time = $time * 10 + 1;
#
#	#everything should be checked now so let's download
#	$ie->getLink( 'linktext:', "download" )->Click;
#	$ie->getRadio( 'value:', "distancematrix" )->Select();
#	$ie->getRadio( 'value:', "jukescantor" )->Select();
#	$ie->getRadio( 'value:', "rdpId" )->Select();
#
#	#$ie->getButton('name:', "modelDload" )->Click();
#
#	#tab until the download button is highlighted
#	for ( 1 .. 16 ) {
#		SendKeys("{TAB}");
#	}
#	SendKeys("{ENTER}");
#	sleep 6;
#	SendKeys("%s");
#
#	my $perlfilename   = "C:/$currentdir/dm/" . $genus . ".txt";
#	my $dialogfilename = "C:\\$currentdir\\dm\\" . $genus . ".txt";
#	unlink $perlfilename;
#	sleep 2;
#	SendKeys("{BACKSPACE}");
#	sleep 1;
#	SendKeys($dialogfilename);
#	SendKeys("%s");
#	sleep $time;
#
#	#hopefully this will ensure that the download dialog looses the focus
#	MouseMoveAbsPix( 1250, 800 );    #a blank area
#	SendMouse("{LEFTCLICK}");
#
#	$ie->Back();                     #to sequence selection page
#}



sub _select_all_sequences {
	my ( $ie, $genus ) = @_;

	if ( $ie->getLink( 'linktext:', $genus ) ) {

		#click the genera link
		$ie->getLink( 'linktext:', $genus )->Click();
	}
	else {
		print "Can't follow $genus link\n";
		$ie->Back();
		return 0;
	}

	if ( $ie->getImage( 'imgurl:', qr/images\/plus.gif/ ) ) {
		$ie->getImage( 'imgurl:', qr/images\/plus.gif/ )->Click();
		print "All $genus sequences selected\n";
		return 1;
	}
	elsif ( $ie->getImage( 'imgurl:', qr/images\/minus.gif/ ) ) {
		print "This taxa ( $genus ) has already been selected!\n";
		return 1;
	}
	elsif ( $ie->getImage( 'imgurl:', qr/images\/gray.gif/ ) ) {
		print "This taxa ( $genus )has no sequences to select!\n";
		$ie->Back();
		return 0;
	}
	else {
		print "Plus link not on this page but should be.\n";
		$ie->Back();
		return 0;
	}
}


