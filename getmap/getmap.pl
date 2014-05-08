#!/usr/bin/perl -w
#@(#)$Revision: 1.12 $

# A Perl script, which demonstrates the capabilities of the QualysGuard
# API.

# With this script you can run maps, run maps and store the results
# on Qualys servers, list, and display the stored maps.

# Indentation style: 1 tab = 4 spaces

use HTTP::Request;
use LWP::UserAgent;
require XML::Twig;

my $myname = "getmap";

my $map_count = 0;	# Saved map count, from map_report_list response
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

sub key {
	my ($xml, $element) = @_;

	printf "%s: %s\n", $element->att('value'), $element->trimmed_text;
}

sub map {
	my ($xml, $element) = @_;

	# For a map results, just return the XML

	printf "%s\n", $result->content;
}

sub map_report {
	my ($xml, $element) = @_;

	$map_count++;	# Saw a list element, bump up the count

	printf "Map Ref: %s\n   Date: %s\n Domain: %s\n\n", $element->att("ref"), $element->att("date"), $element->att("domain");
}

sub map_report_list {
	my ($xml, $element) = @_;
}

sub scan_running_list {
	my ($xml, $element) = @_;
}

sub scan {
	my ($xml, $element) = @_;
}

sub usage {
	printf STDERR "usage: %s username password {{cancel|delete|retrieve} ref|list|running_list|{map|save} domain {iscanner_name}}\n", $myname;
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

my $show_url = 0;

if ($ARGV[2] eq "-v") {
	splice @ARGV, 2, 1;
	$show_url = 1;
}

# XML::Twig is a handy way to process an XML document. We use it to attach
# various handlers, which are triggered whenever related tags are found
# in the XML document. We also attach an error() handler, which is
# triggered whenever Twig finds any errors. Note: The "process comments"
# attribute is useful to recognize and return the error message
# text. Finally, the generic_return() handler covers the case where a
# <GENERIC_RETURN> element is encountered.

if ($ARGV[2] eq "map" or $ARGV[2] eq "save") {
	usage if ($#ARGV < 3 or $#ARGV > 5);	# Need at least a Domain name or list to continue

	# Check for multiple domains to select map-2.php or map.php as appropriate.

	my $map_api = ($ARGV[3] =~ /[,\;:]/) ? "map-2" : "map";

	$url  = "https://$server/msp/${map_api}.php?domain=$ARGV[3]";	# map
	$url .= "&save_report=yes" if ($ARGV[2] eq "save");				# save

	# Check if iscanner_name parameter is present.

	if ($#ARGV > 3) {
		if ($#ARGV == 4) {
			$url .= "&iscanner_name=$ARGV[4]";						# appliance
		} else {
			usage;
		}
	}

	$xml = new XML::Twig(
		TwigHandlers => {
			ERROR             => \&error,
			GENERIC_RETURN    => \&generic_return,
			MAP               => \&map,
		}
	);
} elsif ($ARGV[2] eq "list") {	# Needs no attributes
	$url = "https://$server/msp/map_report_list.php";

	$xml = new XML::Twig(
		TwigHandlers => {
			ERROR             => \&error,
			GENERIC_RETURN    => \&generic_return,
			MAP_REPORT_LIST   => \&map_report_list,
			MAP_REPORT        => \&map_report,
		},
		comments => 'keep'
	);
} elsif ($ARGV[2] eq "retrieve") {
	usage if ($#ARGV != 3);		# Need a map ref to continue
	$url = "https://$server/msp/map_report.php?ref=$ARGV[3]";

	$xml = new XML::Twig(
		TwigHandlers => {
			ERROR             => \&error,
			GENERIC_RETURN    => \&generic_return,
			MAP               => \&map,
		}
	);
} elsif ($ARGV[2] eq "delete") {
	usage if ($#ARGV != 3);		# Need a map ref to continue
	$url = "https://$server/msp/scan_report_delete.php?ref=$ARGV[3]";

	$xml = new XML::Twig(
		TwigHandlers => {
			ERROR             => \&error,
			GENERIC_RETURN    => \&generic_return,
		},
		comments => 'keep'
	);
} elsif ($ARGV[2] eq "running_list") {	# Needs no attributes
	$url = "https://$server/msp/scan_running_list.php";

	$xml = new XML::Twig(
		TwigHandlers => {
			ERROR             => \&error,
			GENERIC_RETURN    => \&generic_return,
			KEY               => \&key,
			SCAN_RUNNING_LIST => \&scan_running_list,
			SCAN              => \&scan,
		},
		comments => 'keep'
	);
} elsif ($ARGV[2] eq "cancel") {
	usage if ($#ARGV != 3);		# Need a map ref to continue
	$url = "https://$server/msp/scan_cancel.php?ref=$ARGV[3]";

	$xml = new XML::Twig(
		TwigHandlers => {
			ERROR             => \&error,
			GENERIC_RETURN    => \&generic_return,
		},
		comments => 'keep'
	);
} else {
	usage;
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

if ($ARGV[2] eq "list") {
	if ($map_count) {
		printf "Saved Maps: %1d total\n", $map_count if ($map_count > 1);
	} else {
		print  "No saved maps found\n";
	}
}
