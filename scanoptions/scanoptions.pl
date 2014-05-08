#!/usr/bin/perl -w
#@(#)$Revision: 1.11 $

# A Perl script, which demonstrates the capabilities of the QualysGuard
# API.

# With this script you can list or set the scan option profiles for
# your account.

# Indentation style: 1 tab = 4 spaces

use HTTP::Request;
use LWP::UserAgent;
require XML::Twig;

my $myname = "scanoptions";

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

sub loadbalancer {
	my ($xml, $element) = @_;

	printf "  Load Balancer: %s\n", $element->att('value');
}

sub ports {
	my ($xml, $element) = @_;

	printf "          Ports: %s%s\n", $element->att('range'), $element->trimmed_text ? sprintf " (%s)", $element->trimmed_text : "";
}

sub scandeadhosts {
	my ($xml, $element) = @_;

	printf "Scan Dead Hosts: %s\n", $element->att('value');
}

sub scanneroptions {
	my ($xml, $element) = @_;

	print "Scanner Options\n";
}

sub usage {
	printf STDERR "usage: %s.pl username password {list|set [loadbalancer [ports [scandeadhosts]]]}\n", $myname;
	print  STDERR "\nloadbalancer={yes|no}\n";
	print  STDERR "\nports={default|full|<custom range>}\n\n";
	print  STDERR "<custom range> is a comma-seperated list of port numbers,\nor ranges of port numbers, separated by dashes (for example, 8000-8888).\n";
	print  STDERR "\nscandeadhosts={yes|no}\n";
	printf  STDERR "\nExample: > perl ./%s.pl login pass set no full yes\n\n",$myname;
	exit 1;
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

# Check for at least username, password, and command

usage if ($#ARGV < 2);

if ($ARGV[2] eq "list") {
	usage if ($#ARGV > 2);
	$url = "https://$server/msp/scan_options.php";
} elsif ($ARGV[2] eq "set") {
	usage if ($#ARGV > 5);
	$url  = "https://$server/msp/scan_options.php?";
	$url .= "loadbalancer=$ARGV[3]&" if ($ARGV[3]);
	$url .= "ports=$ARGV[4]&"        if ($ARGV[4]);
	$url .= "scandeadhosts=$ARGV[5]" if ($ARGV[5]);
} else {
	usage;
}

# XML::Twig is a handy way to process an XML document. Here, we attach
# a handler, which is triggered whenever a tag is found
# in the XML document. We also attach an error() handler, which is
# triggered whenever Twig finds any errors. Note: The "comments"
# attribute is useful to recognize and return the error message
# text. Finally, the generic_return() handler covers the case where a
# <GENERIC_RETURN> element is encountered.

$xml = new XML::Twig(
	TwigHandlers => {
		ERROR          => \&error,
		GENERIC_RETURN => \&generic_return,
		LOADBALANCER   => \&loadbalancer,
		PORTS          => \&ports,
		SCANDEADHOSTS  => \&scandeadhosts,
	},
	comments => 'keep',
);

$xml->setStartTagHandlers({SCANNEROPTIONS => \&scanneroptions});

# Setup the request

$request = new HTTP::Request GET => $url;

# Create an instance of the authentication user agent

my $ua = authUserAgent->new;

# Make the request

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
