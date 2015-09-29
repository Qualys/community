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
$0 : A program to execute the Qualysguard hostdetection API.
	
usage : $0 [-dfh]
	
-f	: first time run (output all to date)
-d  : only pull data from DATE YYYY-MM-DD
-h 	: this (help) output
		
EOF
exit;
}

our %opt; our $DATE = ""; our $FULLPULL = 0;
getopts('hfd:', \%opt) or usage();
usage() if $opt{h};
$FULLPULL = 1 if defined $opt{f};
$DATE = $opt{d} if defined $opt{d};

our $APIURL = "https://qualysapi.qg2.apps.qualys.com";
our $API_USER = "XXXXXXX"; our $API_PWD = "XXXXXXXX";

our $UA; our $RESPONSE; 

#if ($opt{e} eq "QA") {
	#}
#else { usage(); exit; }


my $AGENT_STR = "Jeff Leggett for Qualys";
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

login();

# Build the correct URL to call
our $URL = $APIURL . "/api/2.0/fo/asset/host/vm/detection/?action=list&output_format=XML";
$URL = $URL . "&suppress_duplicated_data_from_csv=0&status=Active,New,Re-Opened,Fixed&";
$URL = $URL . "active_kernels_only=0";
 
if (defined $opt{d}) { $URL = $URL . "&vm_scan_since=$opt{d}"; }

my $REQ = HTTP::Request->new(POST => $URL);
#s$REQ->authorization_basic($API_USER, $API_PWD);
my $RESULT = $UA->request($REQ);
if (! $RESULT->is_success) {
	my $ERROR = $RESULT->status_line;
	print "Failed to get the hostdetection data: $ERROR";
	logout();
}


# Save the output
my $content = $RESULT->content;
open( XMLOUT, ">hostdetection_out.xml" );
print XMLOUT $content;
close XMLOUT;

logout();
