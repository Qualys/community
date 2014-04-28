#!/usr/bin/perl -w

my @agent_string = ("fetchreport-7.0Beta");

=head1 NAME

20111228 - API requests rewriten using WWW::Curl::Easy instead of LWP. Provides better support of proxy.
20111228 - Changing default authentication method to BASIC to avoid session expiration.
20110523 - added support for basic authentication. Recommended settings.
20110523 - changed report polling intervals. The script checks if the report has been generated every 2 hours.
20110523 - added countdown timer.

fetchreport-6.0 Beta Revision: 1.01
20110511 - added support for report title
20110511 - added support for generate report only / don't download the report
20110505 - support for remediation reports
20110426 - support for asset_group_ids= API parameter.
20101215 - support added for encrypted pdf distribution list

=head1 SYNOPSIS

This script launches a QualysGuard automatic report with the specified
template id and output format, then checks the status of the running report
periodically to see whether it is finished and saves a copy to the specified
file in the local filesystem.

NOTE: This script is intended primarily for demonstration purposes, and
reasonable care should be used when deploying it in a production environment.
For example:

1) For heaven's sake, don't run this script (or any other script that fails
   to validate or sanitize incoming parameters) in SUID mode.

2) If you run this script on a multi-user system then be sure to tweak the
   configuration so that the cookie jar file is created in a directory whose
   contents cannot be snooped by another user.

To make sure you are running the latest versions of the perl libraries, or to install these libraries, run the following command:
run cpan as root: > sudo cpan
At the prompt, run the command:
	install CPAN
	reload cpan
	install strict
	install Data::Dumper
	install Getopt::Long
	install WWW::Curl::Easy
	

=head1 DESCRIPTION

See usage() defined at the bottom of this script.

=head1 EXAMPLES

fetchreport.pl --username=foo --password=bar --reportid=123 --format=pdf --path=/home/foo --serverurl=https://qualysapi.qualys.com

=cut

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use WWW::Curl::Easy;

# Define a few more global variables:
my $STARTUP_DELAY = 300; # default is 300. Gives new reports a chance to show up in the report center. 300 seconds = 5 minutes
my $POLLING_DELAY = 7200; # default is 7200. Time to wait between report completion checks. 7200s = 2 hours
my $MAX_NOT_FOUND_CHECKS = 2; # default is 2. 300 + 7200*2 = 14700 seconds = 4 hours 5 minutes
my $MAX_RUNNING_CHECKS = 24; # default is 24. 300 + 7200*24 = 173100 seconds = 2 days and 5 minutes
my $FETCH_ATTEMPTS = 5; # default is 5. Tries to fetch the report up to 5 times
my $FETCH_DELAY = 20; # default is 20. Waits 20 seconds before trying to fetch the report again

# define the asset_group_id for the "All" Asset Group
# Use the asset_group_list.php function to find asset group IDs that correspond to asset group titles.
# To be used with report_type=Remediation
# Example: curl -u USER:PASS https://qualysapi.qualys.com/msp/asset_group_list.php
#
# REQUIRED TO BE UPDATED WITH THE ACTUAL VALUE OF YOUR SUBSCRIPTION
#
my $All_asset_group_id = 105212;

my ($username, $password, $template_id, $format, $path, $proxy, $proxy_username, $proxy_password, $debug, $file,
    $server_url, $pdf_password, $report_type, $recipient_group, $ag_ids, $generate_only, $report_title, $authentication) =
    ('', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '');

GetOptions('username=s'        => \$username,		'password=s'        => \$password,		 'reportid=s'      => \$template_id,
           'format=s'          => \$format,			'path=s'            => \$path,			 'proxy=s'         => \$proxy,
           'proxy_username=s'  => \$proxy_username, 'proxy_password=s'  => \$proxy_password, 'debug=s'         => \$debug,
           'serverurl=s'       => \$server_url,     'ag_ids=s'		    => \$ag_ids,         'pdf_password=s'  => \$pdf_password,
           'report_type=s'     => \$report_type,    'recipient_group=s' => \$recipient_group,'generate_only=s' => \$generate_only,
           'authentication=s'  => \$authentication, 'report_title=s'    => \$report_title);

usage("Improper parameters.") if ($username eq '' || $password eq '' || $template_id eq '' || $format eq '' || $path eq '' || $server_url eq '' ||
                ($format ne 'pdf' && $pdf_password ne '') || ($format ne 'pdf' && $recipient_group ne ''));
usage("'pdf_password' must be set when 'recipient_group' is provided.") if ($recipient_group ne '' && $pdf_password eq '');
usage("Improper value '$authentication' for 'authentication' parameter. Must be 'session' or 'basic'.") if (! ($authentication eq  '' || $authentication eq  'basic' ||
				$authentication eq 'session'));

# Emit starting timestamp:
my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
($debug eq "y" || $debug eq "yy") && print "$hour:$min:$sec\n";

# Create curl object with global parameter
my $curl = WWW::Curl::Easy->new();
my @header = ("X-Requested-With: Perl Curl Easy");
my $response_body;
if ($proxy) {
	$proxy =~ s/http:\/\///i;
}
$curl->setopt(CURLOPT_PROXY, $proxy) if ($proxy);
if (!$authentication) {
	$authentication = 'basic';
}
$curl->setopt(CURLOPT_USERNAME, $username) if ($username && ($authentication eq 'basic'));
$curl->setopt(CURLOPT_PASSWORD, $password) if ($password && ($authentication eq 'basic'));
$curl->setopt(CURLOPT_HEADER,1);
$curl->pushopt(CURLOPT_HTTPHEADER, \@agent_string);
$curl->pushopt(CURLOPT_HTTPHEADER, \@header);
$curl->setopt(CURLOPT_WRITEDATA,\$response_body);

$server_url =~ s/https:\/\///i;
################ BEGINING main function ###################
$debug eq "y" && print "URL = $server_url\n";
$debug eq "yy" && print "URL = $server_url\n";
login() if ($authentication ne 'basic');

my $id = launch_report();

if (! $generate_only) {
	# generate and download the report
	wait_for_report($id);
	fetch_report($id);
} else {
	print "\nOption 'generate_only' has been set. The report with title=\"$report_title\" (id = $id) is being generated and saved in your subscription.\n\n";
}

logout() if ($authentication ne 'basic');

# ending timestamp
($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
($debug eq "y" || $debug eq "yy") && print "$hour:$min:$sec\n";

print "Done\n";
exit(0);
################ END main function ###################

# Log in the global $ua object and set the QualysSession cookie
# or die with an error.
sub getapiresult {
	my($method, $request, $arg, $exit, @junk) = @_;
	my $ret_output = '';
	
	# If using session API, the header must be returned to capture the session cookie
	#if ($request =~ m/api\/2.0\/fo\/session/) {
	#	$curl->setopt(CURLOPT_HEADER,1);
	#}
	
	if (($debug eq 'y') || ($debug eq 'yy')) {
		print("requesting 'https://" . $server_url . $request . "?" . $arg . "' using method " . $method . "\n");
	}

	my $q_url = 'https://' . $server_url . $request;
	if ($method eq "GET") {
		$q_url = $q_url . "?" . $arg;
		$curl->setopt(CURLOPT_POST, 0);
		$curl->setopt(CURLOPT_POSTFIELDS, "");
	}
	if ($method eq "POST") {
		$curl->setopt(CURLOPT_POST, 1);
		$curl->setopt(CURLOPT_POSTFIELDS, $arg);
	}
	
	$curl->setopt(CURLOPT_URL, $q_url);

	# Starts the actual request
	my $retcode = $curl->perform;

	# don't display response if this is not an API output <=> (content-type = text/xml)
	# for instance, don't display a PDF/XML/ZIP/CSV report
	if ((($debug eq 'y') || ($debug eq 'yy')) && (grep(/Content-Type: text\/xml/, split(/\n/, $response_body)))) {
		print("<API_OUTPUT>\n" . $response_body . "\n</API_OUTPUT>\n");
	}
	
	# Looking at the results...
	if ($retcode == 0) {
	        #print("Transfer went ok\n");
	        #my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
	        # judge result and next action based on $response_code
	        #print("Received response: $response_body\n");
	        $ret_output = $response_body;
	} else {
	        # Error code, type of error, error message
	        print("An error happened: $retcode ".$curl->strerror($retcode)." ".$curl->errbuf."\n");
	        my $msg = "Request 'https://" . $server_url . $request . "?" . $arg . "' using method " . $method . " FAILED\n";
	        quit($msg) if ($exit);
	        print($msg);
	}

	# reset curl option for the next requests
	$curl->setopt(CURLOPT_URL, "");
	$curl->setopt(CURLOPT_POST, 0);	
	$curl->setopt(CURLOPT_POSTFIELDS, "");
	$response_body = '';
	return $ret_output;
}

sub login {
    print "Logging in.\n";
    
    my $arg = 'action=login&username=' . $username . '&password=' . $password;
    my $res = getapiresult('POST', '/api/2.0/fo/session/', $arg);
	my @res1 = split(/\n/, $res);
    if (!grep(/Logged in/, @res1)) {
    	quit("login FAILED");
    }
    my @cookie = grep(/Set-Cookie:/, @res1);
    $cookie[0] =~ s/Set-Cookie/Cookie/;
	$curl->pushopt(CURLOPT_HTTPHEADER, \@cookie);
}

# Log out the global $ua object or die with an error.
sub logout {
    print "Logging out.\n";
    
    my $arg = 'action=logout';
    my $res = getapiresult('POST', '/api/2.0/fo/session/', $arg);
}

# Log out the global $ua object (so as not to leave a dangling
# FO session), print the passed message, and die.
sub quit {
    my($mesg, @junk) = @_;
    logout() if ($authentication ne 'basic');
    die("Exiting with Error: " . $mesg);
}

# Launch a new Report Center report with the global report template_id
# and output format and return the associated id, or exit gracefully
# with an error (don't leave any dangling FO sessions).
sub launch_report {
	print "Launching report.\n";

	my $post_data = 'action=launch&output_format=' . $format . '&template_id=' . $template_id;
	
	if ($report_title) {
		($debug eq "y" || $debug eq "yy") && print "report title has been provided\n";
		$post_data .= '&report_title=' . $report_title;
	}

	if ($ag_ids) {
		($debug eq "y" || $debug eq "yy") && print "asset_group_ids IS NOT empty\n";
		$post_data .= '&asset_group_ids=' . $ag_ids;
	}

	if ($format eq 'pdf' && $pdf_password ne '' && $recipient_group ne '') {
		($debug eq "y" || $debug eq "yy") && print "format IS PDF AND pdf_password is NOT empty AND group is NOT empty\n";
		$post_data .= 'pdf_password=' . $pdf_password;
        $post_data .= 'recipient_group=' . $recipient_group;
	}

	if ($format eq 'pdf' && $pdf_password ne '' && $recipient_group eq '') {
		($debug eq "y" || $debug eq "yy") && print "format IS PDF AND pdf_password is NOT empty AND group IS empty\n";
		$post_data .= '&pdf_password=' . $pdf_password;
	}
	
	if ($report_type eq 'Remediation') {
		($debug eq "y" || $debug eq "yy") && print "report type = Remediation\n";
		$post_data .= '&report_type=Remediation';
		$post_data .= '&assignee_type=All';
		if (!$ag_ids) {
			$debug eq "y" && print "asset_group_ids IS All AND report_type IS Remediation\n";
			$post_data .= '&asset_group_ids=' . $All_asset_group_id;
		}
	}
	
	my $res = getapiresult('POST', '/api/2.0/fo/report/', $post_data);
    my $id = -1;
    # For real XML parsing we use XML::Simple or XML::Twig,
    # but for checking simple API responses like we can get
    # away with a direct pattern match:
    if ($res =~ /VALUE>(\d+)<\/VALUE/) {
    	$id = $1;
    }
    if ($id < 0) {
        # launch failure
        if ($debug eq 'yy') {
            print "DEBUG - Launch response:\n" . Dumper($res);
        }
        if ($debug eq 'y') {
            print "DEBUG - Launch response:\n" . $res;
        }
        quit('Launch failed!');
    }
    return $id;
}

# create a coutdown time to indicate the remaining time to wait
# take a number of seconds as a parameter
sub my_sleep {
	my($num_seconds, $sleep_message, @junk) = @_;

	print "$sleep_message\n";
	if ($debug eq 'yy') {
	    $|++;
	    while ($num_seconds--) {
	    	sleep 1;
	    	print "\rRemaining seconds to wait: $num_seconds                ";
	    }
	    $|--;
	    print "\n";
	} else {
		print "Wait $num_seconds seconds\n";
		sleep($num_seconds);
	}
}

# Poll the Report Center until the report with the passed id shows
# up with statue "Finished", or is not found for more than 5 minutes
# (suggesting that it was never actually launched), or is "Runnning"
# for more than 3 days (suggesting that it is hung), or shows up
# as having Errors or having been Cancelled, in which case we exit
# gracefully with an error (don't leave any dangling FO sessions).
sub wait_for_report {
    my($id, @junk) = @_;
    my $not_found_checks = 0;
    my $running_checks = 0;
    my $found = 0;
	my $state = 'Not Found';
    my $percent = '';
    
    print 'Waiting for Report Center id ' . $id . " to finish...\n";
    my_sleep($STARTUP_DELAY,"Initial timer to give a chance to the report to finish in less than $STARTUP_DELAY seconds");
    while (1) {
        my $res = getapiresult('GET', '/api/2.0/fo/report/', 'action=list&id=' . $id);
        # For real XML parsing we use XML::Simple or XML::Twig,
        # but for checking simple API responses like we can get
        # away with a direct pattern match:
        if ($res =~ /STATE>(\S+)<\/STATE/) {
        	$state = $1;
        }
        if ($res =~ /PERCENT>(\S+)<\/PERCENT/) {
            $percent = '(' . $1 .'% complete)';
        }

        if ($state eq 'Finished') {
            $found = 1;
            last;
        } else {
            if ($state eq 'Running') {
                $running_checks++;
                if ($running_checks > $MAX_RUNNING_CHECKS) {
                    quit('Report ' . $id . " has been running in the Report Center for too long - giving up!\n");
                }
            } elsif ($state eq 'Not Found') {
                $not_found_checks++;
                if ($not_found_checks > $MAX_NOT_FOUND_CHECKS) {
                    quit('Report ' . $id . " hasn't shown up in the Report Center after more than a minute - giving up!\n");
                }
            } else {
                # $state must be either 'Canceled' or 'Errors'
                quit('Report ' . $id . ' has state ' . $state . " and so cannot be fetched!\n");
            }
            print '   ' . $state . ' ' . $percent . "...\n";
        }
        my_sleep($POLLING_DELAY,"Next API call to check the report availability");
    }
}

# Fetch the Report Center with the passed id and dump the contents
# to a local file, or exit gracefully with an error (don't leave
# any dangling FO sessions).
sub fetch_report {
    my($id, @junk) = @_;
	my $res = '';
	my $file_format;
	
	if ($format eq 'html') {
		$file_format = 'zip';
	} else {
		$file_format = $format;
	}

	# Don't fetch if default value of FETCH_ATTEMPTS is 0 (zero)
	# if you want to launch the report only, use option --generate_only
	if (!$FETCH_ATTEMPTS) {
		   	exit(0);
    }

	while ($FETCH_ATTEMPTS) {
		$FETCH_ATTEMPTS--;
		print("Fetching Report Center id " . $id . " -- Attempt(s) remaining " . $FETCH_ATTEMPTS . "\n");
		$res = getapiresult('GET', '/api/2.0/fo/report/', 'action=fetch&id=' . $id, 0);
		if (!($res =~ /<CODE>7001<\/CODE>/)) {
			$FETCH_ATTEMPTS = 0;
		} else {
        	# fetch failure
        	if ($debug eq 'yy') {
            	print "DEBUG - Fetch response:\n" . Dumper($res);
        	}
        	if ($debug eq 'y') {
            	print "DEBUG - Fetch response:\n" . $res;
        	}
        	if (!$FETCH_ATTEMPTS) {
        		quit('Fetch failed!');
        	}
    	}
       	if ($FETCH_ATTEMPTS) {
		   	my_sleep($FETCH_DELAY,"Wait $FETCH_DELAY seconds before retrying to download the report");
       	}
	}
    ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
    # default filename is as per old fetchreport.pl
    $file = $path . '/generic_report_nameT' . sprintf("%02d%02d%02d", $hour, $min, $sec) . '.' . $file_format;
    if ($res =~ /filename=(.*)/) {
        # QWEB download filename trumps default filename
        my $variable='';
        ($variable) = ( $1 =~ /(.*).$file_format/ );
        $file = $variable . "_" . sprintf("%02d%02d%02d", $hour, $min, $sec) . '.' . $file_format;
        $file = "$path/$file";
    }

    print "Writing $file\n";
    open F, ">$file" or quit("Unable to open output file for writing: $!");
    binmode(F);
    my ($s_header, $s_body) = split(/Content-Type.*\n/, $res);
	print("HEADER = $s_header\n\n");

    print F (split(/\n/,$s_body,2))[1];
    close F;
}

# Indicate which command line arguments are supported and/or required
sub usage {
	my($usage_message, @junk) = @_;
	print "\n$usage_message\n\n";
    print <<EOF;
fetchreport.pl [arguments]

 Required Arguments:
  --username=SOMEUSER          QualysGuard username
  --password=SOMEPASS          Password for username
  --reportid=SOMENUMBER        Numeric Report Template ID
  --format=[mht|pdf|html|xml]  Report format
  --path=SOMEPATH              Output directory
  --serverurl=https://SOMEURL  Platform server url for launching reports. Must start with https://

 Optional Arguments:
  --proxy=http://USER:PASS\@SOMEURL:PORT     HTTPS proxy URL with option USER LOGIN for proxy auth.
  --pdf_password               Password for PDF encrypted reports (can only be used with option
                               --format=pdf)
  --recipient_group            List of groups for PDF encrypted reports (can only be used with
                               option --format=pdf and --pdf_password MUST be set)
  --ag_ids					   List of Asset Groups ID when requesting a REMEDIATION report. Set to
                               0 for 'All'. Make sure the variable All_asset_group_id is properly
                               set in this perl script
  --debug=y                    Outputs additional information
  --debug=yy                   Outputs lots of additional information
  --report_type=[Scan|Remediation]	 'Scan' is the default value. For 'Remediation' the default
                               value for 'assignee_type' is 'All' (All users)
  --generate_only=[1|0]        Only generates the report saved in the QualysGuard report share. The
                               report is not downloaded localy. Default is 0
  --report_title=text          default report title is empty unless this option is set
  --authentication=[basic|session]   'basic' is the default and recommended value to avoid any
                               potential expired session issue
                               
EOF
    exit;
}
