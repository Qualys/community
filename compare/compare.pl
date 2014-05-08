#!/usr/bin/perl -w
#@(#)$Revision: 1.9 $

# A Perl script, which demonstrates the capabilities of the QualysGuard
# API.

# This script executes a scan for an IP address or block of IP
# addresses and tallies up the total vulnerabilities found. Then, it
# compares the current tally against the results of the previous scan,
# if any, and reports whether things are more secure, less secure,
# or the same.

# Indentation style: 1 tab = 4 spaces

use HTTP::Request;
use LWP::UserAgent;
require XML::Twig;

my $myname = "compare";

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

sub scan_report {
	my ($xml, $scan_report) = @_;

	# Find a report that contains the exact target IP address
	# or range.

	if ($scan_report->att('target') eq $ARGV[2]) {
		# If it's the most recent, then use it for the comparison.

		if ($scan_report->att('date') gt $xml->{latestMatchDate}) {
			$xml->{latestMatchDate} = $scan_report->att('date');
			$xml->{latestMatchRef}  = $scan_report->att('ref');
		}
	}
}

sub timestamp {
	# Return a syslog-like timestamp string (for example,
	# Sep 12 05:19:48)

	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime;

	return sprintf "%s %2d %02d:%02d:%02d", (Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Nov, Oct, Dec)[$mon], $mday, $hour, $min, $sec;
}

sub usage {
	printf STDERR "usage: %s username password ip [option-profile-name|\"null\"] [iscanner-name]\n", $myname;
	exit 1;
}

sub vuln {
	my ($xml, $vuln) = @_;

	# Add up all of the vulnerability severity attributes, one at
	# a time when this handler is called for each <VULN>

	$xml->{vulnScore} += $vuln->att('severity');
}

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

$url = "https://$server/msp/scan_report_list.php";

# XML::Twig is a handy way to process an XML document. Here, we attach
# scan_report() and vuln() handlers, which are triggered whenever
# <SCAN_REPORT> or <VULN> tags are found in the XML document. We also
# attach an error() handler, which is triggered whenever Twig finds
# any errors. Note: The "comments" attribute is useful to recognize and
# return the error message text. Finally, the generic_return() handler
# covers the case where a <GENERIC_RETURN> element is encountered.

$xml = new XML::Twig(
	TwigHandlers => {
		ERROR          => \&error,
		GENERIC_RETURN => \&generic_return,
		SCAN_REPORT    => \&scan_report,
		VULN           => \&vuln,
	}
);

# Initialize attributes

$xml->{latestMatchDate} = "";
$xml->{latestMatchRef}  = "";

# Initialize the vulnScore attribute

$xml->{vulnScore} = 0;

# Find latest previous scan that matches the current scan IP range

my $ua = authUserAgent->new;

# Setup the request

$request = new HTTP::Request GET => $url;

# Issue the request

printf "%s Obtaining the list of saved scans\n", &timestamp;
print STDERR $url . "\n" if ($show_url);
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

# Save the scan_ref for use later

my $comparison_ref = $xml->{latestMatchRef};
printf "%s Scan Ref %s selected, run date: %s\n", &timestamp, $comparison_ref, $xml->{latestMatchDate} if ($comparison_ref);

# Setup the scan request

$url  = "https://$server/msp/scan.php?ip=$ARGV[2]&save_report=yes";
$url .= "&option=$ARGV[3]"        if ($ARGV[3] and lc($ARGV[3]) ne "null");
$url .= "&iscanner_name=$ARGV[4]" if ($ARGV[4]);

$request = new HTTP::Request GET => $url;

# Issue the request

printf "%s Running scan for %s (this will take a few minutes)\n", &timestamp, $ARGV[2];
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

my $ScanScore = $xml->{vulnScore};

# Retrieve previous scan, if any, for comparison

if ($comparison_ref) {
	# Initialize vulnScore attribute

	$xml->{vulnScore} = 0;

	# Setup the request

	$url = "https://$server/msp/scan_report.php?ref=$comparison_ref";
	$request = new HTTP::Request GET => $url;

	# Issue the request

	printf "%s Retrieving %s for comparison\n", &timestamp, $comparison_ref;
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

	# Compare scores

	printf "%s Comparing scan scores\n", &timestamp;

	if ($ScanScore == $xml->{vulnScore}) {
		printf "Network security is the same (score: %1d)\n", $ScanScore;
	} elsif ($ScanScore > $xml->{vulnScore}) {
		printf "Network vulnerability increased (current score: %1d, earlier score: %1d, change: +%1d)\n", $ScanScore, $xml->{vulnScore}, $ScanScore - $xml->{vulnScore};
	} else {
		printf "Network vulnerability decreased (current score: %1d, earlier score: %1d, change: %1d)\n", $ScanScore, $xml->{vulnScore}, $ScanScore - $xml->{vulnScore};
	}
} else {
	# No previous scan found

	printf "No previous scan for %s exists for comparison.\nCurrent network security score is %1d.\n", $ARGV[2], $ScanScore;
}
