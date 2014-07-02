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
my $UA; 

# must give an environment to work on - QA or PROD
#
my %opt; 
getopts('he:', \%opt) or usage();
usage() if $opt{h};

if ($opt{e} eq "POD2") {
	$APIURL = "https://qualysapi.qg2.apps.qualys.com";
	$API_USER = "xxxxxx";
	$API_PWD = "yyyyyyy";
}
elsif ($opt{e} eq "POD1") {
	$APIURL = "https://qualysapi.qualys.com";
	$API_USER = "xxxxxx";
	$API_PWD = "yyyyyyy";
}

#Configure the User Agent 
my $AGENT_STR = "Generic User Agent";
$UA = LWP::UserAgent->new('agent'                => $AGENT_STR,
                             'requests_redirectable' => [],
                             'timeout'               => 900);
$UA->ssl_opts( verify_hostnames => 0 ); 
$UA->default_header('X-Requested-With' => $AGENT_STR);
$UA->cookie_jar({});
my $COOKIEJAR = HTTP::Cookies->new();


# Log in the global $UA object and set the QUAlysSession cookie
# or die with an error.
print "Logging in...\n";
my $r = POST($APIURL . '/api/2.0/fo/session/', ['action' => 'login','username' => $API_USER,'password' => $API_PWD]);
my $RESPONSE = $UA->request($r);
print "DEBUG - Login RESPONSE:\n" . $RESPONSE->content if ($debug);
die("Login failed with info:\n".Dumper($RESPONSE)) unless ($RESPONSE->is_success);
    
# Get the session cookie - it looks like this:
# QUAlysSession=b91647c540ab2d45edde245c7b9a9db1; path=/api; secure
my $cookie = $RESPONSE->{'_headers'}->{'set-cookie'};
$cookie =~ m/QualysSession=(.*);.*;.*/;


#example scanner listing
my $URL = $APIURL . "/api/2.0/fo/appliance/?action=list";
my $REQ = HTTP::Request->new(GET => $URL);
$REQ->authorization_basic($API_USER, $API_PWD);
my $RESULT = $UA->request($REQ);
my $XMLCONTENT = $RESULT->content;
if (! $RESULT->is_success) {
	my $ERROR = $RESULT->status_line;
	die "Failed to fetch scanner list with error: $ERROR";
}

#print Dumper($REQ);

open (XMLOUT, ">scannerlist.xml");
#my $XMLP->parse($RESULT);
print XMLOUT $XMLCONTENT;
close XMLOUT;

my $xml = XML::LibXML->load_xml(location => 'scannerlist.xml');

foreach my $scanner #($xml->findnodes('/APPLIANCE_LIST_OUTPUT/RESPONSE/APPLIANCE_LIST/APPLIANCE')) {
($xml->findnodes('//APPLIANCE_LIST_OUTPUT//APPLIANCE')) {
	my $scanname = $scanner->findnodes('./NAME');
	my $status = $scanner->findnodes('./STATUS');
	print $scanname->to_literal . "," . $status->to_literal . "\n";
}	

# Log out the global $UA object or die with an error.
print "Logging out...\n";
$RESPONSE = $UA->post($APIURL . '/api/2.0/fo/session/', ['action' => 'logout']);
print "DEBUG - Logout RESPONSE:\n" . $RESPONSE->content if ($debug);
die("Logout failed with info:\n".Dumper($RESPONSE)) unless ($RESPONSE->is_success);
