#!/usr/bin/perl -w

use strict;
use Getopt::Std;
use Excel::Writer::XLSX;
use Text::CSV;
use File::Copy;

sub usage()
{
	print STDERR << "EOF";
$0 : Produce the combined report from a Patch, Scorecard and 
Vulnerability Report.  Output to a single EXCEL workbook. 
	
usage : $0 [-h -p file -s file -v file]
	
-p	: Patch Report File
-s	: Scorecard Report File
-v  : Vulnerability Report file
-h  : the help output
	
example : $0 -p Patch_Report_DataCenter_AIX___Patch_Sample_hxxxx_xx_20140912.csv -s Scorecard_Report_DataCenter_AIX_hxxxx_xx_20140912.csv -v Scan_Report_DataCenter_AIX___Example_hxxx_xx_20140912.csv

If you do not VERY CAREFULLY use the same Asset Groups/Asset Tags with the
SAME option profiles and search lists, and carefully maintain that across all 3
of the reports used for input to this program, you will get very inconsistent
results most likely, and confuse your target audience.
				* * * YOU HAVE BEEN WARNED * * *
EOF
	exit;
}
print "\n\nIf you do not VERY CAREFULLY use the same Asset Groups/Asset Tags with the\n";
print "SAME option profiles and search lists, and carefully maintain that across all 3\n";
print "of the reports used for input to this program, you will get very inconsistent\n";
print "results most likely, and confuse your target audience. \n ";
print "* * * YOU HAVE BEEN WARNED * * *\n\n\n";

our $SCOREFILE = ""; our $PATCHFILE = ""; our $VULNFILE = "";
our @PATCHESBYHOST; our @PATCHLIST; our @SUMMARYDATA;
my %opt; 

my @EMPTYLIST = ("\n", "\n");
getopts('hp:s:v:', \%opt) or usage();
if ($opt{h}) {usage(); exit; }
if ($opt{p} eq "") { die "Must give a Patch report file\n"; }
else { $PATCHFILE = $opt{p}; }
#print $PATCHFILE . "\n";

if ($opt{s} eq "") { die "Must give a Scorecard report file\n"; }
else { $SCOREFILE = $opt{s}; }
#print $SCOREFILE . "\n";

if ($opt{v} eq "") { die "Must give a Scan report file\n"; }
else { $VULNFILE = $opt{v}; }

# Setup Vars used throughout each sheet
our $LINE = 0; my $FOUND = 0;

# should set binary attribute
my $csv = Text::CSV->new ( { binary => 1 } ) or die "Cannot use CSV: ".Text::CSV->error_diag (); 

#Create the Workbook and setup the worksheets... Creation order here will 
# be the order the worksheets appear.  We'll rename it when we are done.
my $WORKBOOK = Excel::Writer::XLSX->new('combinedreport.xlsx');
my $SUMMARY = $WORKBOOK->add_worksheet('Summary');
my $PATCHLIST = $WORKBOOK->add_worksheet('Patch List');
my $PATCHHOST = $WORKBOOK->add_worksheet("Patches by Host");

# Process Scorecard CSV
our $SCORECARD = $WORKBOOK->add_worksheet('Scorecard');
our @ROW; my $STATUS; my @TROW; my $TROW;
our $REPORTNAME;
# Setup our headerinfo
push @SUMMARYDATA, "Vulnerability & Patch Summary for:";

# Process scorecard report and build the Summary Data                 			
open my $FH, "<$SCOREFILE" or die ("Can't open $SCOREFILE: $!");
while ( our $ROW = $csv->getline( $FH ) ) {
	# Get an array reference to the line of data
 	my $A_REF = \@$ROW;
	# Write it out to the worksheet on the correct row
	$SCORECARD->write_row($LINE,0,$A_REF);
	if ($ROW->[0] =~ m/RESULTS/) { $FOUND = 1; next; }
	if ($LINE == 0) { 
		#print $ROW->[0];
		$TROW = $ROW->[0] . "\n"; 
		chomp $TROW;  
		$TROW =~ s/ Scorecard Report//; 
		# We use this at the end to name the report appropriately.
		$REPORTNAME = $TROW;
		push @SUMMARYDATA, $TROW; }
	if ($FOUND == 1) { 
		@TROW = @$ROW; # just for clarity
		splice @TROW, 4,3; 
		push @SUMMARYDATA, join(",",@TROW);
	}
	$LINE++;
}
push @SUMMARYDATA, join(",",@EMPTYLIST);
if ($FOUND == 0) { warn "We never found Results section in Scorecard!\n"; }

$csv->eof or $csv->error_diag();
close $FH;
	
# Process Patch CSV
our $PATCHES = $WORKBOOK->add_worksheet('Patch Details');
open $FH, "<$PATCHFILE" or die ("Can't open $PATCHFILE: $!");
$LINE = 0; $FOUND = 0;
while ( our $ROW = $csv->getline( $FH ) ) {
	# Get an array reference to the line of data
	my $A_REF = \@$ROW;
	# Write it out to the worksheet on the correct row
	$PATCHES->write_row($LINE,0,$A_REF);
	# Set flags for the portion we want to cut out to add to another tab and 
	# make them into a an array we can use to create the new tabs afterwards.
	if ($ROW->[0] =~ m/Patch List/) { $FOUND = 1; print "Found Patch List!\n"}
	if ($ROW->[0] =~ m/Patches by Host/) { $FOUND = 2; print "Found Host Patch list\n"; } 
	if ($ROW->[0] =~ m/Host Vulnerabilities Fixed by Patch/) { $FOUND = 0; }
	if ($ROW->[0] =~ m/Patch Summary/) { $FOUND = 3; }
	if ($FOUND == 1) { push @PATCHLIST, $ROW; }	
	if ($FOUND == 2) { push @PATCHESBYHOST, $ROW; }
	if ($FOUND == 3) { push @SUMMARYDATA, join(",",@$ROW); }
	$LINE++;		
}
push @SUMMARYDATA, join(",",@EMPTYLIST);
print "Patches by Host: " . scalar @PATCHESBYHOST . "\n";	
print "Patch List: " . scalar @PATCHLIST . "\n";
close $FH;

$LINE = 0; $FOUND = 0;
#Process Scan Report
my $VULNDATA = $WORKBOOK->add_worksheet('Vuln Details');
open $FH, "<$VULNFILE" or die ("Can't open $VULNFILE: $!");
$LINE = 0;
while ( our $ROW = $csv->getline( $FH) ) {
	# Get an array reference to the line of data
 	my $A_REF = \@$ROW;
	# Write it out to the worksheet on the correct row
	$VULNDATA->write_row($LINE,0,$A_REF);
	if ($ROW->[0] =~ m/Total Vulnerabilities/) { $FOUND = 1; }
	if ($ROW->[0] =~ m/IP/) { $FOUND = 0;}
	if ($FOUND == 1) { push @SUMMARYDATA, join(",",@$ROW); }
	$LINE++;
}
close $FH;
push @SUMMARYDATA, join(",",@EMPTYLIST);
#Write my Patch list out to a tab
$LINE = 0;
foreach (@PATCHLIST) {
	#print $_ . "\n";
	$PATCHLIST->write_row($LINE,0,$_);
	$LINE++;
}

#Write my Patches by Host out to a tab
$LINE = 0;
foreach (@PATCHESBYHOST) {
	#print $_ . "\n";
	$PATCHHOST->write_row($LINE,0,$_);
	$LINE++;
}


$LINE = 0;
foreach (@SUMMARYDATA) {
	print TEMPFILE $_ . "\n";
	$SUMMARY->write_row($LINE, 0, $_);
	$LINE++;
}
close TEMPFILE;

$LINE = 0;
open $FH, "</tmp/tmp.csv";
while ( our $ROW = $csv->getline( $FH ) ) {
	# Get an array reference to the line of data
 	my $A_REF = \@$ROW;
	#print $A_REF . "\n";
	# Write it out to the worksheet on the correct row
	
	$TROW = join(",",@$ROW);
	#print $TROW;
	$SUMMARY->write($LINE,0,$A_REF); 
	$LINE++;
}
close $FH;

$WORKBOOK->close();

#Build the Spreadsheet name into one based on the reports.
$REPORTNAME =~ s/ /_/;
$REPORTNAME = $REPORTNAME . "_combinedreport.xlsx";
#print $REPORTNAME;
copy("combinedreport.xlsx", $REPORTNAME);
unlink "combinedreport.xlsx";
unlink "/tmp/tmp.csv";

