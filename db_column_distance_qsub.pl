#!/usr/bin/perl
#
# column_distance_qsub.pl
#
# Torque must be installed on your server to use this script.
#
# This program allows large distance matrices to be broken into smaller jobs
# by submitting multiple column_distance.pl jobs via the qsub command.
#
# The jobs will be approximately the same size in terms of how many pairwise
# sequence distance calculations they will be asked to do.
#
# Note: commandline flags are not used so order is important. See Usage.
#
# Usage: perl column_distance_run.pl <fastafilename> <scriptname> <numjobs>
#
# fastafilename: the fasta filename to calculate distance matrix with
# scriptname:    the shellscript name for this/these job/jobs
# numjobs:       the number of jobs/cpu's to use with Torque's qsub command
# this allows a user to break up the jobs into smaller pieces
# 
# e.g:
# perl column_distance_run.pl Bacteria.Bacteroidetes.Bacteroidia.Bacteroidales.Prevotellaceae__Prevotella.nodupe.fa Prev 10
#
# This command would create 10 jobs from the .fa file, using shell scripts named Prev.1, Prev.2, etc.
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
use Config::Tiny;


my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'probeset.conf' );
my $currentdir = getcwd;
#same load and save dirs as column_distance.pl
my $loaddir = $currentdir."/".$Config->{remove_duplicate_sequences}->{savedir}."/";
my $savedir = $currentdir."/".$Config->{column_distance}->{savedir}."/";
#load values specific to column_distance_qsub.pl
my $sleeptime = $Config->{column_distance_qsub}->{waitTimeBetweenQsubs}."/";
my $scriptdir = $currentdir."/".$Config->{column_distance_qsub}->{scriptdir}."/";
unless( -d $scriptdir ) {
	mkdir $scriptdir || die "Error: unable to create directory $savedir.";
}


#get commandline arguments
my ($fastafilename, $scriptname, $pieces) = @ARGV;
undef @ARGV;#undef clears standard input so '<>' operates correctly later
my $piece=1;

unless(defined $pieces) {
		die "Usage: perl column_distance_qsub.pl <fastafilename> <scriptname> <numjobs>\n";
}
die "Can't find $loaddir.$fastafilename!" unless( -e  $loaddir.$fastafilename );


#print particulars for job(s) and ask for verification
print
		"nodupe fasta source directory=".$loaddir.
		"\ndistance matrix save directory=".$savedir.
		"\nfasta filename=".$fastafilename.
		"\nshell script=".$scriptname.
		"\nparts to make=".$pieces.
		"\n";

print "Is this correct (y/n)?\n";
my $r=<>;
exit unless($r=~/^y/i);


#create a shell script for each job and qsub them
for(my $job=1; $job<=$pieces; $job++) {

	chdir $scriptdir;#necessary to keep qsub output in the same directory
	#open(SHELL, ">".$scriptdir.$scriptname.$job) || die "Can't open shell file $scriptname!\n$!\n";
	open(SHELL, ">".$scriptname.$job) || die "Can't open shell file $scriptname!\n$!\n";

	print SHELL 

	'#!/bin/sh'."\n".
	"cd $currentdir/\n".
	"perl d_column_distance.pl \"$fastafilename\" $pieces $piece\n";

	$piece++;
	close SHELL;
	sleep 1;

	my $command = "qsub ".$scriptdir.$scriptname.$job;
	print $command."\n";
	system $command;
	sleep $sleeptime unless($job==$pieces);#no need to sleep after last job
}


