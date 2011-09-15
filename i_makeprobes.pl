#!/usr/bin/perl
#
# makeprobes.pl
#
# This program runs best_probes.o to make probe sets
#
# Usage: perl makeprobes.pl
#

use strict;
use Cwd;
use Config::Tiny;

my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( 'probeset.conf' );
my $currentdir = getcwd;
my $loaddir = $currentdir."/".$Config->{sequences2matrix_by_otu}->{savedir}."/";
my $savedir = $currentdir."/".$Config->{makeprobes}->{savedir}."/";

my $probe_sets_to_make = $Config->{makeprobes}->{probe_sets_to_make};
my $input_matrix_file = $Config->{makeprobes}->{input_matrix_file};
my $good_probes_file = $Config->{makeprobes}->{good_probes_file};
my $bad_probes_file = $Config->{makeprobes}->{bad_probes_file};

my $i = $Config->{makeprobes}->{number_iteration_fixed_temperature};
my $n = $Config->{makeprobes}->{number_probes};
my $x = $Config->{makeprobes}->{number_experiments};
my $s = $Config->{makeprobes}->{steepness};
my $t = $Config->{makeprobes}->{penalty_standard};
my $o = $Config->{makeprobes}->{penalty_otu};
my $g = $Config->{makeprobes}->{penalty_genus};
my $p = $Config->{makeprobes}->{penalty_phylum};
my $r = $Config->{makeprobes}->{random_seed};
my $d = 0;#depreciated. do not change this value
unless( -d $loaddir ) {
	die "Error: specified directory of matrix files does not exist.\n";
}
unless( -d $savedir ) {
	mkdir $savedir || die "Error: unable to create directory $savedir.";
}

#set special Perl variables for printing
$,="\n";

#make probe filename prefix
my $probefile = $input_matrix_file;
$probefile =~ s/matrix$/probes/;


#count how many probes are actually in the matrix file
open(FILE, "<", $loaddir.$input_matrix_file) || die "Can't open $loaddir.$input_matrix_file\n$!\nEnsure the probeset.conf file's input_matrix_file value is the same as your matrix file name.\n";
my $lines;
while( <FILE> ) { $lines++; }
my $c = ($lines-4)/2;#this count becomes an argument to best_probes.o
print $input_matrix_file." has $c probes in file\n";
close FILE;

#prepare parameters for inclusion into the probe set's filenames
my $penalt = "_o".$o."g".$g."p".$p."t".$t."d".$d;
my $params = "_i".$i."_n".$n."_x".$x."_s".$s;

#create probe sets with given parameters
for my $pset (1 .. $probe_sets_to_make) {
	my $pset = sprintf("%03s", $pset);
	my $command = $currentdir."/"."best_probes.o "
		."-o $o -g $g -p $p -t $t -d $d "
		."-i $i -n $n -x $x -c $c -s $s "
		."-f $loaddir$input_matrix_file ";
	$command = $command."-k $good_probes_file " if length $good_probes_file > 0;
	$command = $command."-b $bad_probes_file " if length $bad_probes_file > 0;
	$command = $command."> ".$savedir.$probefile.$penalt.$params."_r".$pset.".txt\n";

	my $pfilename =  $savedir.$probefile.$penalt.$params."_r".$pset.".txt";
	print $command."\n";
	if(-e $pfilename) {
		print "File exists. Overwritting...\n";
	}
	system $command;
}

exit;

