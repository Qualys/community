#!/usr/bin/perl

=head1 NAME

lastScanInfo.pl

=head1 SYNOPSIS

This script uses the QualysGuard API to get the last scan time and scanner for the specified IP.

=head1 DESCRIPTION

See usage() defined at the bottom of this script.

=head1 EXAMPLES

lastScanInfo.pl --user=foo --password=bar --serverurl=https://qualysapi.qualys.com --ip=10.1.1.1

=cut

#---------------------------------------
#
# Use clauses
#
#---------------------------------------
use strict;
use LWP::UserAgent;
#use LWP::Debug qw(+); # uncomment this to see LWP debug messages
use HTTP::Request;
use HTTP::Response;
use HTTP::Cookies;
use HTTP::Request::Common;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use XML::Twig;
use POSIX qw(strftime);
use Date::Parse;
use URI::Escape;


#---------------------------------------
#
# Globals
#
#---------------------------------------
my $appname = basename($0);
my $version = '1.0.0';
my ($username, $password, $server_url, $help, $proxy, $proxy_username, $proxy_password, $debug, $outputFile, $ip, $usefile, $scanRef, $retStr);
my $logFile= basename($0, '.pl').".log";
my $DAY = (24 * 60 *60);

my $xmlFile = '';
# Get a decent temp file to use
(undef, $xmlFile) = tempfile("sepXXXXXX", SUFFIX => ".xml", OPEN => 0);
my %hostInfo = (TOTAL => 0, SEPINSTALLED => 0, SEPRUNNING => 0, CURRENT => 0, OUTDATED => 0, UNKNOWN => 0, NOSEP => 0 );
my %vulnInfo;
my $validDate;

# Get command line options
GetOptions('username=s'       => \$username,
           'password=s'       => \$password,
           'proxy=s'          => \$proxy,
           'proxy_username=s' => \$proxy_username,
           'proxy_password=s' => \$proxy_password,
           'serverurl=s'      => \$server_url,
           'verbose'          => \$debug,
           'help'             => \$help,
           'outfile=s'        => \$outputFile,
           'ip=s'             => \$ip,
           'usefile=s'        => \$usefile);

# Does the user want help?
usage() if ($help);

# Make sure we have all the arguments.
my $msg = '';
my $errStr = 'ERROR - Missing argument';
$msg .= 'username,' unless ($username);
$msg .= 'password,' unless ($password);
$msg .= 'serverurl,' unless ($server_url);
$msg .= 'ip,' unless ($ip);

# Get rid of a trailing comma for neatness
chop($msg);

# Are we supposed to use a file?
$xmlFile = $usefile if ($usefile);

# Make message plural or not
$errStr .= 's' if ($msg =~ /,/);
usage("$errStr: $msg") if ($msg);

# Use default output file if not specified
$outputFile = basename($0, '.pl').".csv" unless ($outputFile);

# Make sure we can write to the output file
usage("ERROR - cannot write to output file $outputFile") unless ((-w $outputFile) || !(-e $outputFile)) ;

# URI-escape the IP
$retStr = "Asset $ip";
$ip = uri_escape($ip);


# Configure the user agent
$ENV{'HTTPS_PROXY'} = $proxy if ($proxy);
$ENV{'HTTPS_PROXY_USERNAME'} = $proxy_username if ($proxy_username);
$ENV{'HTTPS_PROXY_PASSWORD'} = $proxy_password if ($proxy_password);
$ENV{HTTPS_PKCS12_FILE}     = '';
$ENV{HTTPS_PKCS12_PASSWORD} = '';
my $agent_string = $appname .'$Revision: '.$version.' $';
my $ua = LWP::UserAgent->new('agent'                => $agent_string,
                             'requests_redirectable' => [],
                             'timeout'               => 900);
$ua->default_header('X-Requested-With' => $agent_string);

# Open the log
open(LOGFILE, ">>$logFile");

# Emit starting timestamp
&logPrint('INFO',"$appname starting up...");

#---------------------------------------
#
# Main script starts here
#
#---------------------------------------

# Get the asset data
&getData('ip');

# Process the data
&processIPData();

# Get scan infomation
&getData('scan');

# Find Scanners
&getScannerList();

print "$retStr\n";

# Ending timestamp
&logPrint('INFO',"$appname finished.");

# Close the log
close(LOGFILE);

# Done!
&cleanUp(0);

# Indicate which command line arguments are supported and/or required
sub usage {
  my $msg = shift;
  $msg = "$appname $version" unless $msg;
  print <<EOF;

$msg 

$appname [arguments]

  Required Arguments:

    --username=SOMEUSER          QualysGuard username
    --password=SOMEPASS          Password for username
    --serverurl=https://SOMEURL  Platform server url for launching reports
    --ip=w.x.y.z                 The IP to get information for
    
  Optional Arguments:

    --proxy=http://SOMEURL       HTTPS proxy URL
    --proxy_username=SOMEUSER    HTTPS proxy USERNAME
    --proxy_password=SOMEPASS    HTTPS proxy PASSWORD
    --verbose                    Outputs log information to STDOUT
    --outfile=SOMEFILE           A file to output to; if not specified, will default to $appname.csv
    --help                       Provide usage information (what you are reading)

$appname will get the last scan time and scanner for the specified IP.

Example:

./lastScanInfo.pl --username=foo --password=bar --ip=10.1.1.1 --serverurl=https://qualysapi.qualys.com
Asset 10.1.1.1 was scanned during scan/1315938346.36085 with scanners is_foo_az1 (Scanner 5.17.57-1, Vulnerability Signatures 1.28.210-2)


EOF

    &cleanUp(1);
}


# Routine to call asset_data_report.php
sub getData
{
	
  my $type = shift;
  
  # Skip this if we already have the file
  return if (-e "$type-$xmlFile");

  my $url = "$server_url/msp/";
  if ($type eq 'ip') {
	$url .= "scan_report_list.php?target=$ip&last=yes";
  } else {
	$url .= "scan_report.php?ref=$scanRef";
  }

  my $req = HTTP::Request->new(GET => $url);
  $req->authorization_basic($username, $password);
  my $res = $ua->request($req);  
  &logPrint('INFO', "Getting data from API at:  $url");
    
  if (! $res->is_success){
    my $error   = $res->status_line;
    &logPrint('ERROR', "Failed to fetch data with error: $error");
    &cleanUp(1);
  }
  # Save the results to a file
  open(MYFILE, ">$type-$xmlFile");
  binmode(MYFILE);
  print MYFILE $res->content;
  close(MYFILE);
}


# Routine to process the Data
sub processIPData
{
	
  # Let's create a new twig
  my $twig= new XML::Twig( twig_handlers => { SCAN_REPORT => \&getReport } );
  # Parse the twig
  $twig->parsefile( "ip-$xmlFile" );
  
}


# Routine to get scan reference
sub getReport
{
  # Passed in the vuln information
  my ($twig, $scan) = @_;
  
#  Get the scan ref
  $scanRef = $scan->{'att'}->{'ref'};
  &logPrint('INFO',"Ref: $scanRef\n");
  $retStr .= " was scanned during $scanRef";
  $twig->purge;
  
}


# Routine to process the Data
sub getScannerList
{
	
  # Let's create a new twig
  my $twig= new XML::Twig( twig_handlers => { KEY => \&getScanners } );
  # Parse the twig
  $twig->parsefile( "scan-$xmlFile" );
  
}

# Routine to get scaners
sub getScanners
{
  # Passed in the vuln information
  my ($twig, $hosts) = @_;
  
  return unless ($hosts->{'att'}->{'value'} eq 'SCAN_HOST');
  &logPrint('INFO',"Scanner: ".$hosts->first_child_text);
  $retStr .= " with scanner(s) ".$hosts->first_child_text;
  $twig->purge;
  
}


# Routine to print to the log
sub logPrint
{
  my ($sevStr, $msg) = @_;
  my $timestamp = POSIX::strftime("%m/%d %H:%M:%S", localtime()); 
  my $entry = "$timestamp|$sevStr|$msg\n";

  # Send the entry to the logfile if we have a good file number
  print LOGFILE $entry if (fileno(LOGFILE));
  # Print to STDOUT if we have the --debug flag, or if we don't have a good file number
  print $entry if ($debug || (!fileno(LOGFILE)));
}


# Routine to clean up when exiting
sub cleanUp
{
  my $exitCode = shift;
  # Close the log file
  close(LOGFILE);
  # Delete the temporary file
  unlink("ip-$xmlFile") unless ($usefile);
  unlink("scan-$xmlFile") unless ($usefile);
  exit($exitCode);
}
