#!/usr/bin/perl -w
#@(#)$Revision: 1.4 $

# A Perl script, which demonstrates the capabilities of the QualysGuard
# API.

# This script demonstrates how to get the version strings from the
# QualysGuard server. It also provides an example of how to list the
# available time zone codes.

# Indentation style: 1 tab = 4 spaces

use HTTP::Request;
use LWP::UserAgent;
require XML::Twig;

my $myname = "about";

my $request;	# HTTP request handle
my $result;		# HTTP response handle
my $server;		# QualysGuard server's FQDN hostname
my $url;		# API access URL
my $xml;		# Twig object handle

my ($time_zone_code, $time_zone_details);	# "about time" vars

# Handlers and helper functions

sub api_version {
	my ($xml, $element) = @_;

	printf "      API Version: %1d.%1d\n", $element->att('MAJOR'), $element->att('MINOR');
}

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

sub scanner_version {
	my ($xml, $element) = @_;

	printf "  Scanner Version: %s\n", $element->trimmed_text;
}

sub vulnsigs_version {
	my ($xml, $element) = @_;

	printf "Vuln Sigs Version: %s\n", $element->trimmed_text;
}

sub web_version {
	my ($xml, $element) = @_;

	printf "     QWEB Version: %s\n", $element->trimmed_text;
}

sub time_zone_code {
	my ($xml, $element) = @_;

	$time_zone_code = $element->trimmed_text;
}

sub time_zone_details {
	my ($xml, $element) = @_;

	$time_zone_details = $element->trimmed_text;
}

sub observe_dst {
	my ($xml, $element) = @_;

	printf "TZ Code: %s %s\nDetails: %s\n\n",
		$time_zone_code,
		($element->trimmed_text eq '1') ? "(Daylight Savings Time supported)" : "",
		$time_zone_details;
}

# $server may be read from the shell environment, or defaults to
# qualysapi.qualys.com otherwise.

if ($ENV{QWSERV}) {
	$server = $ENV{QWSERV};
} else {
	$server = "qualysapi.qualys.com";
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

sub usage {
	printf STDERR "usage: %s username password [time_zone_codes]\n", $myname;
	exit 1;
}

my $ltzc = 0;	# Default: Don't list time zone codes

if ($#ARGV == 1) {
	$url = "https://$server/msp/about.php";
} elsif ($#ARGV == 2) {
	if ($ARGV[2] =~ /time/) {
		$url = "https://$server/msp/time_zone_code_list.php";
		$ltzc = 1;
	} else {
		usage;
	}
} else {
	usage;
}

# XML::Twig is a handy way to process an XML document. Here, we attach the
# handlers, which are triggered whenever a registered tag is found in the
# XML document. We also attach an error() handler, which is triggered
# whenever Twig finds any errors. Note: The "comments" attribute is
# useful to recognize and return the error message text.

if ($ltzc) {
	$xml = new XML::Twig(
		TwigHandlers => {
			'DST_SUPPORTED'     => \&observe_dst,
			'ERROR'             => \&error,
			'GENERIC_RETURN'    => \&generic_return,
			'TIME_ZONE_CODE'    => \&time_zone_code,
			'TIME_ZONE_DETAILS' => \&time_zone_details,
		}
	);
} else {
	$xml = new XML::Twig(
		TwigHandlers => {
			'API-VERSION'      => \&api_version,
			'ERROR'            => \&error,
			'GENERIC_RETURN'   => \&generic_return,
			'SCANNER-VERSION'  => \&scanner_version,
			'VULNSIGS-VERSION' => \&vulnsigs_version,
			'WEB-VERSION'      => \&web_version,
		}
	);
}

# Setup the request

$request = new HTTP::Request GET => $url;

# Create an instance of the authentication user agent

my $ua = authUserAgent->new;

# Make the request

$result = $ua->request($request);

# Check result

if ($result->is_success) {
	# Parse the XML

	$xml->parse($result->content);
} else {
	# An HTTP related error

	printf STDERR "HTTP Error: %s\n", $result->status_line;
	exit 1;
}
