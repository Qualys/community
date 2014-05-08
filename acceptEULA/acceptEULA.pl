#!/usr/bin/perl -w
#@(#)$Revision: 1.6 $

# A Perl script, which demonstrates the capabilities of the QualysGuard
# API.

# This script demonstrates how to programatically accept the Qualys
# terms and conditions. In order to use the API you must first present
# the terms and conditions to your application users.

# Indentation style: 1 tab = 4 spaces

use HTTP::Request;
use LWP::UserAgent;
require XML::Twig;

my $myname = "acceptEULA";

my $request;	# HTTP request handle
my $result;		# HTTP response handle
my $server;		# QualysGuard server's FQDN hostname
my $url;		# API access URL
my $xml;		# Twig object handle

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
	printf STDERR "usage: %s username password\n\nusername: The QualysGuard username who wishes to accept the End User Licensing Agreement (EULA).\npassword: The user's password\n", $myname;
}

# XML::Twig is a handy way to process an XML document. Here, we attach
# a scan() handler, which is triggered whenever a <SCAN> tag is found
# in the XML document. We also attach an error() handler, which is
# triggered whenever Twig finds any errors. Note: The "comments"
# attribute is useful to recognize and return the error message
# text. Finally, the schedscans() handler covers the case where a
# <SCHEDULEDSCANS> tag is encountered.

$xml = new XML::Twig(
	TwigHandlers => {
		ERROR          => \&error,
		GENERIC_RETURN => \&generic_return,
	},
	comments => 'process'
);

if ($#ARGV != 1) {
	usage;
	exit 1;
} else {
	$url = "https://$server/msp/acceptEULA.php";
}

# Setup the request

$request = new HTTP::Request GET => $url;

# Create an instance of the authentication user agent

my $ua = authUserAgent->new;

# Make the request

$result = $ua->request($request);

# Check result

if ($result->is_success) {
	$xml->parse($result->content);
} else {
	# An HTTP related error

	printf STDERR "HTTP Error: %s\n", $result->status_line;
	exit 1;
}
