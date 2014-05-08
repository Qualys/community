#!/usr/bin/perl -w
#@(#)$Revision: 1.17 $

# A Perl script, which demonstrates the capabilities of the QualysGuard
# API.

# With this script you can add, delete, and list scheduled scans and
# maps.

# Indentation style: 1 tab = 4 spaces

use HTTP::Request;
use LWP::UserAgent;
require XML::Twig;

my $myname = "scheduledscans";

my $request;	# HTTP request handle
my $result;		# HTTP response handle
my $server;		# QualysGuard server's FQDN hostname
my $url;		# API access URL
my $xml;		# Twig object handle

# Default setting: List both active and inactive scheduled tasks.

my $list_active         = 1;
my $list_inactive       = 1;

# Task type counts: Scan or Map

my $scan_count          = 0;
my $map_count           = 0;

# Task class counts: Active, Inactive, and All

my $active_task_count   = 0;
my $inactive_task_count = 0;
my $task_count          = 0;

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

sub scan {
	my ($xml, $task) = @_;

	# XML::Twig uses a parent-child metaphor to traverse XML, sort of
	# like a directory heirarchy. So, to get the these tags we have to
	# fetch the "active" attribute of that tag to get the scan status.
	#
	# The "ref" attribute is found at the same level.
	#
	# To fetch the text title get the content of the <TITLE> element.
	#
	# To fetch scan targets get the content of the <TARGETS> element.
	#
	# To fetch the next launch date and time get the content of the
	# <NEXTLAUNCH_UTC> element. Careful! For inactive scans, this element
	# will not be present; this case must be handled, too.

	# Get task type: SCAN or MAP

	my $type = $task->first_child('TYPE')->trimmed_text;

	if ($type eq "SCAN") {
		$scan_count++;
	} elsif ($type eq "MAP") {
		$map_count++;
	} else {
		printf STDERR "ERROR: Unrecognized task type: %s\n", $type;
	}

	# Increment task count

	$task_count++;

	# Count the activity attribute: Active or Inactive

	my $active_task;

	if ($task->att('active') eq "yes") {
		$active_task = 1;
		$active_task_count++;
	} else {
		$active_task = 0;
		$inactive_task_count++;
	}

	# Display the task, if it meets the operating activity/inactivity criteria

	if (($list_active && $active_task) || ($list_active && $list_inactive) || ($list_inactive and !$active_task)) {
		printf "         Task ID: %s\n", $task->att('ref');
		printf "          Active: %s\n", $task->att('active');
		printf "           Title: %s\n", $task->first_child('TITLE')->text;
		printf "         Targets: %s\n", $task->first_child('TARGETS')->text;

		if ($active_task) {
			printf "     Next Launch: %s UTC\n", $task->first_child('NEXTLAUNCH_UTC')->text;
		} else {
			printf "     Next Launch: N/A (this task is not active)\n";
		}
		# Dereference to SCHEDULE element

		my $schedule = $task->first_child('SCHEDULE');

		# Dereference to DAILY, WEEKLY, or  MONTHLY element

		my @frequency;
		my $weekdays;

		if ($schedule->first_child('DAILY')) {
			my $daily = $schedule->first_child('DAILY');
			@frequency = ("Frequency Days", $daily->att('frequency_days'));
		} elsif ($schedule->first_child('WEEKLY')) {
			my $weekly = $schedule->first_child('WEEKLY');
			@frequency = ("Frequency Weeks", $weekly->att('frequency_weeks'));
			$weekdays = $weekly->att('weekdays');
			$weekdays = day_names($weekdays) if (defined $weekdays);
		} elsif ($schedule->first_child('MONTHLY')) {
			my $monthly = $schedule->first_child('MONTHLY');
			@frequency = ("Frequency Months", $monthly->att('frequency_months'));
		} else {
			# An XML recognition error; display the XML for the
			# offending element.

			printf "%s\n", $task->print;
		}

		# Dereference to START_DATE_UTC element

		my $start_date_element        = $schedule->first_child('START_DATE_UTC');
		my $start_date                = $start_date_element->trimmed_text;

		my $start_time_hour_element   = $schedule->first_child('START_HOUR');
		my $start_time_hour           = $start_time_hour_element->trimmed_text;

		my $start_time_minute_element = $schedule->first_child('START_MINUTE');
		my $start_time_minute         = $start_time_minute_element->trimmed_text;

		my $time_zone_element         = $schedule->first_child('TIME_ZONE');
		my $time_zone_code_element    = $time_zone_element->first_child('TIME_ZONE_CODE');
		my $time_zone_code            = $time_zone_code_element->trimmed_text;

		my $dst_selected_element      = $schedule->first_child('DST_SELECTED');
		my $dst_selected              = $dst_selected_element->trimmed_text;

		printf "      Start Date: %s UTC\n",        $start_date;
		printf "      Start Time: %02d:%02d UTC\n", $start_time_hour, $start_time_minute;
		printf "       Time Zone: %s%s\n",          $time_zone_code, $dst_selected ? " (Daylight Savings Time active)" : "";
		printf "%16s: Every %s\n",                  @frequency;
		printf "        Weekdays: Every %s\n",      $weekdays if (defined $weekdays);
		printf "  Option Profile: %s\n",            $task->first_child('OPTION')->trimmed_text if ($task->first_child('OPTION'));
		printf "            Type: %s\n\n",          $type;
	}
}

sub schedscans {
	my ($xml, $element) = @_;

	# Check if this is an empty SCHEDULEDSCANS element. If so, there is
	# a comment as the content, which gives more status, so display
	# it.

	if (my $status = $element->first_child_trimmed_text('#COMMENT')) {
		printf "%s\n", $status;
	}
}

sub delete {
	my ($xml, $element) = @_;
	printf "%s\n", $result->content;
}
sub usage {
	printf STDERR "usage: 1) %s username password add [daily|weekly|monthly] [map|scan] title active target option {schedule-attributes} [iscanner_name]\n\n", $myname;
	printf STDERR "       2) %s username password delete task_id\n\n", $myname;
	printf STDERR "       3) %s username password list [scan*|map|all [active|inactive|all*]]\n\n", $myname;
	printf STDERR "Examples\n\n1. Daily map or scan\n\n%s username password add daily [map|scan] title active target option frequency_days time_zone_code observe_dst start_date start_hour start_minute [[[end_after|\"null\"] [recurrence|\"null\"]] [iscanner_name]]\n\n", $myname;
	printf STDERR "2. Weekly map or scan\n\n%s username password add weekly [map|scan] title active target option frequency_weeks weekdays time_zone_code observe_dst start_date start_hour start_minute [[[end_after|\"null\"] [recurrence|\"null\"]] [iscanner_name]]\n\n", $myname;
	printf STDERR "3. Monthly, every Nth day\n\n%s username password add monthly [map|scan] title active target option frequency_months day_of_month time_zone_code observe_dst start_date start_hour start_minute [[[end_after|\"null\"] [recurrence|\"null\"]] [iscanner_name]]\n\n", $myname;
	printf STDERR "4. Monthly, weekday in Nth week\n\n%s username password add monthly [map|scan] title active target option frequency_months day_of_week week_of_month time_zone_code observe_dst start_date start_hour start_minute [[[end_after|\"null\"] [recurrence|\"null\"]] [iscanner_name]]\n", $myname;
	exit 1;
}

# Function to convert comma-separated day numbers to names

sub day_names {
	my ($num_string) = @_;

	my %lookup = (
		0 => "Sunday",
		1 => "Monday",
		2 => "Tuesday",
		3 => "Wednesday",
		4 => "Thursday",
		5 => "Friday",
		6 => "Saturday"
	);

	my $out_string = "";

	if (defined $num_string) {
		my @day_numbers = split ",", $num_string;

		for (@day_numbers) {
			$out_string .= $lookup{$_} . ", ";
		}

		$out_string =~ s/,\s+$//;	# Remove trailing ", "
	}

	return $out_string;
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

# XML::Twig is a handy way to process an XML document. Here, we attach
# a scan() handler, which is triggered whenever a <SCAN>  is found
# in the XML document. We also attach an error() handler, which is
# triggered whenever Twig finds any errors. Note: The "comments"
# attribute is useful to recognize and return the error message
# text. The schedscans() handler covers the case where a
# <SCHEDULEDSCANS> tag is encountered. Finally, the generic_return()
# handler covers the case where a <GENERIC_RETURN> element is
# encountered.

$xml = new XML::Twig(
	TwigHandlers => {
		ERROR          => \&error,
		GENERIC_RETURN => \&generic_return,
		SCAN           => \&scan,
		SCHEDULEDSCANS => \&schedscans,
	},
	comments => 'keep'
);

# Check for at least username, password, and command.

usage if ($#ARGV < 2);

my $show_url = 0;

if ($ARGV[2] eq "-v") {
	splice @ARGV, 2, 1;
	$show_url = 1;
}

if ($ARGV[2] eq "add" and $#ARGV > 2) {
	if ($ARGV[3] eq "daily") {
		if ($#ARGV >= 13 and $#ARGV <= 17) {
			$url ="https://$server/msp/scheduled_scans.php?add_task=yes&scan_title=$ARGV[5]&type=$ARGV[4]&active=$ARGV[6]&scan_target=$ARGV[7]&option=$ARGV[8]&occurrence=daily&frequency_days=$ARGV[9]&time_zone_code=$ARGV[10]&observe_dst=$ARGV[11]&start_date=$ARGV[12]&start_hour=$ARGV[13]&start_minute=$ARGV[14]";
			$url .= "&end_after=$ARGV[15]"     if ($ARGV[15] and lc($ARGV[15]) ne "null");
			$url .= "&recurrence=$ARGV[16]"    if ($ARGV[16] and lc($ARGV[16]) ne "null");
			$url .= "&iscanner_name=$ARGV[17]" if ($ARGV[17]);
		} else {
			usage;
		}
	} elsif ($ARGV[3] eq "weekly" ) {
		if ($#ARGV >= 14 and $#ARGV <= 18) {
			$url = "https://$server/msp/scheduled_scans.php?add_task=yes&scan_title=$ARGV[5]&type=$ARGV[4]&active=$ARGV[6]&scan_target=$ARGV[7]&option=$ARGV[8]&occurrence=weekly&frequency_weeks=$ARGV[9]&weekdays=$ARGV[10]&time_zone_code=$ARGV[11]&observe_dst=$ARGV[12]&start_date=$ARGV[13]&start_hour=$ARGV[14]&start_minute=$ARGV[15]";
			$url .= "&end_after=$ARGV[16]"     if ($ARGV[16] and lc($ARGV[16]) ne "null");
			$url .= "&recurrence=$ARGV[17]"    if ($ARGV[17] and lc($ARGV[17]) ne "null");
			$url .= "&iscanner_name=$ARGV[18]" if ($ARGV[18]);
		} else {
			usage;
		}
	} elsif ($ARGV[3] eq "monthly" and ($#ARGV >= 14 and $#ARGV <= 18)) {
		$url = "https://$server/msp/scheduled_scans.php?add_task=yes&scan_title=$ARGV[5]&type=$ARGV[4]&active=$ARGV[6]&scan_target=$ARGV[7]&option=$ARGV[8]&occurrence=monthly&frequency_months=$ARGV[9]&day_of_month=$ARGV[10]&time_zone_code=$ARGV[11]&observe_dst=$ARGV[12]&start_date=$ARGV[13]&start_hour=$ARGV[14]&start_minute=$ARGV[15]";
		$url .= "&end_after=$ARGV[16]"     if ($ARGV[16] and lc($ARGV[16]) ne "null");
		$url .= "&recurrence=$ARGV[17]"    if ($ARGV[17] and lc($ARGV[17]) ne "null");
		$url .= "&iscanner_name=$ARGV[18]" if ($ARGV[18]);
	} elsif ($ARGV[3] eq "monthly" and ($#ARGV >= 16 and $#ARGV <= 19)) {
		$url = "https://$server/msp/scheduled_scans.php?add_task=yes&scan_title=$ARGV[5]&type=$ARGV[4]&active=$ARGV[6]&scan_target=$ARGV[7]&option=$ARGV[8]&occurrence=monthly&frequency_months=$ARGV[9]&day_of_week=$ARGV[10]&week_of_month=$ARGV[11]&time_zone_code=$ARGV[12]&observe_dst=$ARGV[13]&start_date=$ARGV[14]&start_hour=$ARGV[15]&start_minute=$ARGV[16]";
		$url .= "&end_after=$ARGV[17]"     if ($ARGV[17] and lc($ARGV[17]) ne "null");
		$url .= "&recurrence=$ARGV[18]"    if ($ARGV[18] and lc($ARGV[18]) ne "null");
		$url .= "&iscanner_name=$ARGV[19]" if ($ARGV[19]);
	} else {
		print STDERR "ERROR: add attribute must have values [daily|weekly|monthly] and/or the correct number of arguments.\n\n";
		usage;
	}
} elsif ($ARGV[2] eq "delete") {
	usage if ($#ARGV != 3);
	$url = "https://$server/msp/scheduled_scans.php?drop_task=yes&task_id=$ARGV[3]";
	
	$xml = new XML::Twig(
		TwigHandlers => {
			ERROR          => \&error,
			GENERIC_RETURN => \&generic_return,
			SCHEDULEDSCANS => \&delete,
		},
		comments => 'keep'
	);
	
} elsif ($ARGV[2] eq "list") {
	usage if ($#ARGV < 2 || $#ARGV > 4);

	$url = "https://$server/msp/scheduled_scans.php";

	if ($ARGV[3]) {
		if ($ARGV[3] eq "scan") {
			$url .= "?type=scan";
		} elsif ($ARGV[3] eq "map") {
			$url .= "?type=map";
		} elsif ($ARGV[3] eq "all") {
			$url .= "?type=all";
		} else {
			usage;
		}
	} else {
		$url .= "?type=all";
	}

	if ($ARGV[4]) {
		if ($ARGV[4] eq "active") {
			$list_active   = 1;
			$list_inactive = 0;
		} elsif ($ARGV[4] eq "inactive") {
			$list_active   = 0;
			$list_inactive = 1;
		} else {
			usage if ($ARGV[4] ne "all");
		}
	}
} else {
	usage;
}

# Setup the request

print $url . "\n" if ($show_url);
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

if ($ARGV[2] eq "list") {
	printf "    Task Summary: %1d active, %1d inactive, %1d total\n", $active_task_count, $inactive_task_count, $task_count;
	printf "    Type Summary: %1d scan%s, %1d map%s\n", $scan_count, ($scan_count == 1) ? "" : "s", $map_count, ($map_count == 1) ? "" : "s";
}
