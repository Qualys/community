#!/usr/bin/perl -w
#@(#)$Revision: 1.9 $

# A Perl script, which demonstrates the capabilities of the QualysGuard
# API.

# This script executes a scan for an IP address, or block of IP
# addresses, tallies up the total vulnerabilities found, and displays
# the results. The script also saves the results on the Qualys servers,
# where the scan can be viewed using a web-browser and a link provided
# by the script.

# Indentation style: 1 tab = 4 spaces

use HTTP::Request;
use LWP::UserAgent;
require XML::Twig;

my $myname = "score";

my $request;	# HTTP request handle
my $result;		# HTTP response handle
my $server;		# QualysGuard server's FQDN hostname
my $url;		# API access URL
my $xml;		# Twig object handle

# $server may be read from the shell environment, or defaults to
# qualysapi.qualys.com otherwise.

if ($ENV{QWSERV}) {
	$server = $ENV{QWSERV};
} else {
	$server = "qualysapi.qualys.com";
}

# Handlers and helper functions

sub error {
	my ($xml, $element) = @_;

	my $number = $element->att('number');
	my $message;

	# Some APIs return embedded "<SUMMARY>error summary text</SUMMARY>"
	# elements, so detect and handle accordingly. NOTE: <SUMMARY>
	# elements are usually included for reporting multiple errors with
	# one error element.

	if (!($message = $element->first_child_trimmed_text('SUMMARY'))) {
		$message = $element->trimmed_text;
	}

	if ($number) {
		printf STDERR "Request Status: FAILED\nError Number: %1d\nReason: %s\n", $number, $message;
	} else {
		printf STDERR "Request Status: FAILED\nReason: %s\n", $message;
	}

	exit 255;
}

sub generic_return {
	my ($xml, $element) = @_;

	my ($return, $status, $number, $message);

	# This is a GENERIC_RETURN element. So, display the RETURN element,
	# which gives the detailed status.

	if ($return = $element->first_child('RETURN')) {
		$status  = $return->att('status');
		$number  = $return->att('number');
		$message = $return->trimmed_text;

		if ($number) {
			printf STDERR "Request Status: %s\nError Number: %1d\nReason: %s\n", $status, $number, $message;
		} else {
			printf STDERR "Request Status: %s\nReason: %s\n", $status, $message;
		}
	} else {
		# An XML recognition error; display the XML for the offending
		# element.

		printf STDERR "Unrecognized XML Element:\n%s\n", $element->print;
	}

	exit ($status eq "SUCCESS" ? 0 : 255);
}

sub usage {
	printf STDERR "usage: %s username password {ip [option-profile-name|\"null\"] [iscanner-name]|ref}\n", $myname;
	exit 1;
}

# XML::Twig uses a parent-child metaphor to traverse XML, like a
# directory heirarchy. So, to get the IP address we go up the tree
# three levels to the <IP> tag (from <VULN>) and fetch the "value"
# attribute of that tag to get the IP address. The "severity" attribute
# is found at the same level and is easy to fetch. Finally, the text
# title is the content of the <TITLE> tag.

sub vuln {
	my ($xml, $vuln) = @_;

	# Add up all of the vulnerability severity attributes, one at
	# a time when this handler is called for each <VULN>

	$xml->{vulnScore} += $vuln->att('severity');
}

# The Perl LWP package gives sufficient capabilities to connect to
# the QualysGuard API. To support the HTTP "Basic Authentication"
# scheme, it's necessary to subclass LWP::UserAgent and define a
# method called "get_basic_credentials", which will be called when
# the server challenges the script for authentication. This method
# returns the username and password, which simply are the second and
# third command line parameters.

# A subclass of LWP::UserAgent to handle HTTP Basic Authentication.

{
	package authUserAgent;
	@ISA = qw(LWP::UserAgent);

	sub new {
		my $self = LWP::UserAgent::new(@_);
		$self;
	}

	sub get_basic_credentials {
		return ($ARGV[0], $ARGV[1]);
	}
}

usage if ($#ARGV < 2 or $#ARGV > 5);

my $show_url = 0;

if ($ARGV[2] eq "-v") {
	splice @ARGV, 2, 1;
	$show_url = 1;
}

$url = "https://$server/msp/";

# XML::Twig is a handy way to process an XML document. Here, we attach
# a vuln() handler, which is triggered whenever a <VULN> tag is found
# in the XML document. We also attach an error() handler, which is
# triggered whenever Twig finds any errors. Note: The "comments"
# attribute is useful to recognize and return the error message
# text. Finally, the generic_return() handler covers the case where a
# <GENERIC_RETURN> element is encountered.

$xml = new XML::Twig(
	TwigHandlers => {
		ERROR          => \&error,
		GENERIC_RETURN => \&generic_return,
		VULN           => \&vuln,
	}
);

# Since Perl objects are just hashes, simply attach a new key to
# the hash to keep the score. The reason for doing this is because
# XML::Twig uses callback handlers to deal with element parsing,
# and we never see the return value from the vuln() handler.

$xml->{vulnScore} = 0;

if ($ARGV[2] =~ /^scan/) {
	# Existing scanref case
	# Tip: ref heads are always "scan"

	$url .= "scan_report.php?ref=$ARGV[2]";
	printf "Fetching %s report\n", $ARGV[2];
} else {
	# Run scan case

	$url .= "scan.php?ip=$ARGV[2]&save_report=yes";
	$url .= "&option=$ARGV[3]"        if ($ARGV[3] and lc($ARGV[3]) ne "null");
	$url .= "&iscanner_name=$ARGV[4]" if ($ARGV[4]);

	my $msg  = sprintf("Running scan for %s", $ARGV[2]);
	$msg    .= sprintf(" using option profile %s", $ARGV[3]) if ($ARGV[3] and lc($ARGV[3]) ne "null");
	$msg    .= sprintf(" and appliance %s", $ARGV[4]) if ($ARGV[4]);
	printf "%s (this will take a few minutes)\n", $msg;
}

# Setup the request

$request = new HTTP::Request GET => $url;

# Create an instance of the authentication user agent

my $ua = authUserAgent->new;

# Make the request

print STDERR $url . "\n" if ($show_url);
$result = $ua->request($request);

# Check the result

if ($result->is_success) {
	# Parse the XML

	$xml->parse($result->content);
} else {
	# An HTTP related error

	printf STDERR "HTTP Error: %s\n", $result->status_line;
	exit 1;
}

printf "Total Vulnerability Score: %1d (higher => more vulnerable)\n", $xml->{vulnScore};
printf "To view the complete report, login to https://%s and open the following URL:\nhttps://%s/fo/report/report_view.php?ref=%s&authfirst=true\n", $server, $server, $xml->root->att('value');
