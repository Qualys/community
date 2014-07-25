#!/usr/bin/perl -w
use strict;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTTP::Cookies;
use HTTP::Request::Common;
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
$0 : A program to setup one or more virtUAl scanners in the QUAlys portal.
	
usage : $0 [-eh]
	
-e	: environment (POD1 or POD2)
-h 	: this (help) output
	
example : $0 -e QA
	
EOF
exit;
}

our $APIURL; our $API_USER; our $API_PWD;
our $UA; our $RESPONSE; my $debug;

# must give an environment to work on - QA or PROD
# QA is on POD 2
# PROD is on POD 1
my %opt; 
getopts('he:', \%opt) or usage();
usage() if $opt{h};

# For username and password be sure to setup an API user in Qualysguard
if ($opt{e} eq "QA") {
	$ENVIRONMENT = "POD2";
	$APIURL = "https://qualysapi.qg2.apps.qualys.com";
	$API_USER = "xxxxxx";
	$API_PWD = "xxxxxxx";
}
elsif ($opt{e} eq "POD1") {
	$ENVIRONMENT = "PROD";
	$APIURL = "https://qualysapi.qualys.com";
	$API_USER = "xxxxxx";
	$API_PWD = "xxxxxx";
}
#Delete the file from a previous run so we get a clean one
unlink "authcode_output.xml";
#Configure the User Agent 
my $AGENT_STR = "Jeff Leggett for Customers";
$UA = LWP::UserAgent->new('agent'                => $AGENT_STR,
                          'requests_redirectable' => [],
                          'timeout'               => 900);
$UA->ssl_opts( verify_hostnames => 0 ); 
$UA->default_header('X-Requested-With' => $AGENT_STR);
$UA->cookie_jar({});
my $COOKIEJAR = HTTP::Cookies->new();


# Log in the global $UA object and set the QUAlysSession cookie
# or die with an error.
sub login ()
{
print "Logging in...\n";
my $r = POST($APIURL . '/api/2.0/fo/session/', ['action' => 'login','username' => $API_USER,'password' => $API_PWD]);
$RESPONSE = $UA->request($r);
print "DEBUG - Login RESPONSE:\n" . $RESPONSE->content if ($debug);
die("Login failed with info:\n".Dumper($RESPONSE)) unless ($RESPONSE->is_success);
my $cookie = $RESPONSE->{'_headers'}->{'set-cookie'};
$cookie =~ m/QualysSession=(.*);.*;.*/;
}    
# Get the session cookie - it looks like this:
# QUAlysSession=b91647c540ab2d45edde245c7b9a9db1; path=/api; secure


sub logout ()
{
print "Logging out...\n";
$RESPONSE = $UA->post($APIURL . '/api/2.0/fo/session/', ['action' => 'logout']);
print "DEBUG - Logout RESPONSE:\n" . $RESPONSE->content if ($debug);
die("Logout failed with info:\n".Dumper($RESPONSE)) unless ($RESPONSE->is_success);
}


#MAIN here
#open the list of stores CSV and begin processing one at a time
# The stores.csv file should be a text file with one store name per line
# 
login();

open (STOREFILE, "stores.csv") or die "stores.csv not found\n";
open (ACT_CODES, ">activationcodes.csv") or die "Couldnt open activationcodes.csv\n";
open (XMLLOG, ">scannersetup.txt") or die ("Couldn't open scannersetup.txt");
while (<STOREFILE>) {
	print "Processing Store: " . $_;
	my $STORENAME =  substr($_, 0, -1); 
	#print $STORENAME . "\n";
	#note this change from default polling interval of 180
	my $URL = $APIURL . "/api/2.0/fo/appliance/?action=create&name=" . $STORENAME . "&polling_interval=300";
	# print $URL;
#	my $URL = $APIURL . "/api/2.0/fo/appliance/?action=list";
	my $REQ = HTTP::Request->new(POST => $URL);
	$REQ->authorization_basic($API_USER, $API_PWD);
	my $RESULT = $UA->request($REQ);
	if (! $RESULT->is_success) {
		my $ERROR = $RESULT->status_line;
		print "Failed to create scanner list with error: $ERROR";
		logout();
	}
	my $content = $RESULT->content;
	# Append the file each run through so we hve all the XML post run if needed for someone reason
	# Note running again will  overwrite
	open( XMLOUT, ">>authcode_output.xml" );
	print XMLOUT $content;
	print XMLLOG $content;
	close XMLOUT;
	my $xml = XML::LibXML->load_xml(location => 'authcode_output.xml');
	foreach my $scanner ($xml->findnodes('/APPLIANCE_CREATE_OUTPUT/RESPONSE/APPLIANCE')) {
    	my $scanname = $scanner->findnodes('./FRIENDLY_NAME');
		my $status = $scanner->findnodes('./ACTIVATION_CODE');
		print ACT_CODES $scanname->to_literal . "," . $status->to_literal . "\n";
	}
}
close XMLLOG;
close ACT_CODES;
close STOREFILE;
# Log out the global $UA object or die with an error.
logout();

