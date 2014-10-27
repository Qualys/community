#!/usr/bin/perl -w

use strict;
use LWP;
use Getopt::Std;
use Data::Dumper;
use XML::LibXML qw();

#  need even with ssl_opts verify hostnames off or 0
BEGIN {
	$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0 
};

sub usage()
{
print STDERR << "EOF";
$0 : A program to download reports from the Qualys portal.
	
usage : $0 [-enh]
	
-e	: environment (QA or PROD1 or PROD2)
-n  : report name (case sensitive!  and use double quoes if it has spaces Ex: "DataCenter Unix"
-u  : Qualysguard API User
-p  : Qualyguard API User Password
-h 	: this (help) output
	
example : $0 -e QA -n "DataCenter Linux"
	
EOF
exit;
}

# must give an environment to work on - QA or PROD
my %opt; $opt{n} = "";
getopts('hn:e:', \%opt) or usage();
usage() if $opt{h};

my $ENVIRONMENT = "";
our $APIURL = "";
our $API_USER; our $API_PWD;
our $UA; our $RESPONSE; 

if ($opt{e} eq "POD2") {
	$ENVIRONMENT = $opt{e};
	$APIURL = "https://qualysapi.qg2.apps.qualys.com";
	$API_USER = $opt{u};
	$API_PWD = $opt{p};
}
elsif ($opt{e} eq "POD1") {
	$ENVIRONMENT = $opt{e};
	$APIURL = "https://qualysapi.qualys.com";
	$API_USER = $opt{u};
	$API_PWD = $opt{p};
}
else { usage(); exit; }
if ($opt{n} eq "") { usage(); exit; }
#Delete the file from a previous run so we get a clean one
unlink "report_list.xml";

my $AGENT_STR = "Qualysguard API calls";
$UA = LWP::UserAgent->new('agent'                => $AGENT_STR,
                          'requests_redirectable' => [],
                          'timeout'               => 900);
#$UA->ssl_opts( verify_hostnames => 0 ); 
$UA->default_header('X-Requested-With' => $AGENT_STR);
$UA->cookie_jar({});
my $COOKIEJAR = HTTP::Cookies->new();

# Log in the global $UA object and set the QUAlysSession cookie
# or die with an error.
sub login()
{
print "Logging in...\n";
my $RESPONSE = $UA->post($APIURL . '/api/2.0/fo/session/', ['action' => 'login','username' => $API_USER,'password' => $API_PWD]);
#$RESPONSE = $UA->request($r);
#print "DEBUG - Login RESPONSE:\n" . $RESPONSE->content if ($debug);
die("Login failed with info:\n".Dumper($RESPONSE)) unless ($RESPONSE->is_success);
my $cookie = $RESPONSE->{'_headers'}->{'set-cookie'};
$cookie =~ m/QualysSession=(.*);.*;.*/;
}    
# Get the session cookie - it looks like this:
# QUAlysSession=b91647c540ab2d45edde245c7b9a9db1; path=/api; secure


sub logout()
{
print "Logging out...\n";
$RESPONSE = $UA->post($APIURL . '/api/2.0/fo/session/', ['action' => 'logout']);
# print "Logout RESPONSE:\n" . $RESPONSE->content;
die("Logout failed with info:\n".Dumper($RESPONSE)) unless ($RESPONSE->is_success);
}

sub fetchreport
{
	my $ID = $_[0];
	my $URL = $APIURL . "/api/2.0/fo/report/?action=fetch&id=$ID";
	my $REQ = HTTP::Request->new(GET => $URL);
	#s$REQ->authorization_basic($API_USER, $API_PWD);
	my $RESULT = $UA->request($REQ);
	if (! $RESULT->is_success) {
		my $ERROR = $RESULT->status_line;
		print "Failed to get the report listing: $ERROR";
		logout();
		exit;
	}
	return $RESULT->decoded_content;
}



login();

# Get the list of reports available
my $URL = $APIURL . "/api/2.0/fo/report/?action=list";
my $REQ = HTTP::Request->new(POST => $URL);
#s$REQ->authorization_basic($API_USER, $API_PWD);
my $RESULT = $UA->request($REQ);
if (! $RESULT->is_success) {
	my $ERROR = $RESULT->status_line;
	print "Failed to get the report listing: $ERROR";
	logout();
}
# Save the list 
my $content = $RESULT->content;
open( XMLOUT, ">report_list.xml" );
print XMLOUT $content;
close XMLOUT;

#convert to a CSV with just ID, TITLE and DATE
open REPORTLIST, ">reportlist.csv"; 
my $xml = XML::LibXML->load_xml(location => 'report_list.xml');	
foreach my $REPORT ($xml->findnodes('/REPORT_LIST_OUTPUT/RESPONSE/REPORT_LIST/REPORT')) {
	my $ID = $REPORT->findnodes('./ID');
	my $TITLE = $REPORT->findnodes('./TITLE');
	my $DATE = $REPORT->findnodes('./LAUNCH_DATETIME');
	print REPORTLIST $ID->to_literal . "," . $TITLE->to_literal . "," . $DATE->to_literal . "\n";
}
close REPORTLIST;

my $REPORTNAME = $opt{n};
chomp $REPORTNAME;

print "Looking for /$REPORTNAME/\n";
# Get the latest of the three reports
my @SCORECARD = (); my @PATCH = (); my @VULN = (); 
open REPORTLIST, "<reportlist.csv";
while (<REPORTLIST>) {
	if ($_ =~ m/$REPORTNAME Scorecard/) { push @SCORECARD, $_; }
	if ($_ =~ m/$REPORTNAME Patch/) { push @PATCH, $_; }
	if ($_ =~ m/$REPORTNAME Vuln/) { push @VULN, $_; }
}
close REPORTLIST;

#Sort to get the latest and make sure we got data back
if (@SCORECARD) { @SCORECARD = sort @SCORECARD; } 
else { print " Found no Scorecard reports for $REPORTNAME\n"; logout(); exit;}
if (@PATCH) { @PATCH = sort @PATCH; }
else { print " Found no Patch reports for $REPORTNAME\n"; logout(); exit;}
if (@VULN) { @VULN = sort @VULN; }
else { print " Found no Scan reports for $REPORTNAME\n"; logout(); exit;}

#latest report is at end
my $SCORECARD_ID = ""; my $PATCH_ID = ""; my $VULN_ID = "";
my $REPORTCSV = "";
($SCORECARD_ID, my $JUNK)= split(',', $SCORECARD[-1]);
($PATCH_ID, $JUNK)= split(',', $PATCH[-1]);
($VULN_ID, $JUNK)= split(',', $VULN[-1]);
if ($SCORECARD_ID eq "") { 
	print "No Scorecard report found for $REPORTNAME! Exiting! \n";
	logout();
	exit;
}
elsif ($PATCH_ID eq "") { 
	print "No Patch report found for $REPORTNAME! Exiting! \n";
	logout();
	exit;
}
elsif ($VULN_ID eq "") { 
	print "No Vulnerability report found for $REPORTNAME! Exiting! \n";
	logout();
	exit;
}
else {
	$REPORTNAME =~ s/ /_/;
	print "Downloading SCORECARD report for $REPORTNAME\n";
	$REPORTCSV = fetchreport($SCORECARD_ID);
	open SCORECARD, ">$REPORTNAME" . "_Scorecard_Report.csv";
	print SCORECARD $REPORTCSV;
	close SCORECARD;
	print "Downloading PATCH report for $REPORTNAME\n";
	$REPORTCSV = fetchreport($PATCH_ID);
	open PATCHR, ">$REPORTNAME" . "_Patch_Report.csv";
	print PATCHR $REPORTCSV;
	close PATCHR;
	print "Downloading SCAN/VULN report for $REPORTNAME\n";
	$REPORTCSV = fetchreport($VULN_ID);
	open VULNR, ">$REPORTNAME" . "_Scan_Report.csv";
	print VULNR $REPORTCSV;
	close VULNR;
}
logout();
