#!/usr/bin/perl

=head1 NAME

purgeInactiveAssets

=head1 SYNOPSIS

This script uses the QualysGuard purge API to delete all assets from the
database that have note been scanned since the specified date.

=head1 DESCRIPTION

See usage() defined at the bottom of this script.

=head1 EXAMPLES

purgeInactiveAssets.pl --username=foo --password=bar --date=2010-01-15 --serverurl=https://qualysapi.qualys.com

=cut

#---------------------------------------
#
# Use clauses
#
#---------------------------------------
use strict;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTTP::Cookies;
use HTTP::Request::Common;
use Getopt::Long;
use Data::Dumper;
use File::Basename;
use XML::Simple;
#use LWP::Debug qw(+); # uncomment this to see LWP debug messages

#---------------------------------------
#
# Globals
#
#---------------------------------------
my $appname = basename($0);
my $version = '1.2.0';
my ($username, $password, $startdate, $format, $path, $help, $test, $deltadate,
    $proxy, $proxy_username, $proxy_password, $debug, $file, $server_url) = ('', '', '', '', '', '', '', '', '', '', '', '', '', '');

# Get command line options
GetOptions('username=s'       => \$username,
           'password=s'       => \$password,
           'sincedate=s'      => \$startdate,
           'sincedays=i'      => \$deltadate,
           'proxy=s'          => \$proxy,
           'proxy_username=s' => \$proxy_username,
           'proxy_password=s' => \$proxy_password,
           'debug'            => \$debug,
           'help'             => \$help,
           'test'             => \$test,
           'serverurl=s'      => \$server_url);

# Does the user want help?
usage() if ($help);

# Did we get a day delta? 
$startdate = getnewdate($deltadate) if ($deltadate > 0 );

# Make sure we have all the arguments.
my $msg = '';
my $errStr = 'ERROR - Missing argument';
$msg .= 'username,' unless ($username);
$msg .= 'password,' unless ($password);
$msg .= 'sincedate,' unless ($startdate);
$msg .= 'serverurl,' unless ($server_url);
# Get rid of a trailing comma for neatness
chop($msg);

# Make message plural or not
$errStr .= 's' if ($msg =~ /,/);
usage("$errStr: $msg") if ($msg);

# We should also sanity check the format of the date
usage('ERROR:  Date must be in yyyy-mm-dd') unless ($startdate =~ /(19|20)\d\d-(0[1-9]|1[012])-(0[1-9]|[12][0-9]|3[01])/);

# Set up URL
my $qualysurl = $server_url;

# Emit starting timestamp
my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
print "$appname starting at: $hour:$min:$sec\n" if ($debug);

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
$ua->cookie_jar({});
my $cookiejar = HTTP::Cookies->new();

#---------------------------------------
#
# Main script starts here
#
#---------------------------------------

# Do the login
my $sessionCookie = login();

# Variables to get the list of IDs and whether or not there is more to do
my ($idList, $amDone, $nextBlock) = ('', 0, 0);

# Get the list of hosts - keep look
until ($amDone) {
  
  # Get the listing of IDs, and URL for next get
  ($idList, $nextBlock) = get_hosts($nextBlock);

  # Purge the results
  if ($idList) {
    purge_hosts($idList) unless ($test);
  } else {
    print "No matching hosts.\n";
  }
  
  # Are we done?
  $amDone = ($nextBlock == 0) ? 1 : 0;
}

# Logout and quit.
logout();

# ending timestamp
($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
print "$appname finished at: $hour:$min:$sec\n" if ($debug);
exit(0);

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
    --sincedate=YYYY-MM-DD       Delete data for hosts not scanned since this date.
    --serverurl=https://SOMEURL  Platform server url for launching reports

  Optional Arguments:

    --sincedays=<# of days>      Delete data for hosts not scanned in the specified number of
                                   days.  If specified, this will override any date specified
                                   using the --sincedate argument.
    --proxy=http://SOMEURL       HTTPS proxy URL
    --proxy_username=SOMEUSER    HTTPS proxy USERNAME
    --proxy_password=SOMEPASS    HTTPS proxy PASSWORD
    --debug=y                    Outputs additional information
    --test                       Don't actually do the purge
    --help                       Provide usage information (what you are reading)

$appname will purge all hosts that have not been vulnerability scanned since the specified date
using the QualysGuard API.  Purging hosts will remove automatic host data in the user’s account
(scan results will not be removed). Purged host information will not appear in new reports
generated by users.

Example:

$appname --username=foo --password=bar --sincedate=2010-01-15 --serverurl=https://qualysapi.qualys.com

EOF

    exit(1);
}

# Log in the global $ua object and set the QualysSession cookie
# or die with an error.
sub login {
    print "Logging in...\n";
    my $r = POST($qualysurl . '/api/2.0/fo/session/',
                 ['action' => 'login',
                  'username' => $username,
                  'password' => $password]);
    my $response = $ua->request($r);
    print "DEBUG - Login response:\n" . $response->content if ($debug);
    die("Login failed with info:\n".Dumper($response)) unless ($response->is_success);
    
    # Get the session cookie - it looks like this:
    # QualysSession=b91647c540ab2d45edde245c7b9a9db1; path=/api; secure
    my $cookie = $response->{'_headers'}->{'set-cookie'};
    $cookie =~ m/QualysSession=(.*);.*;.*/;
    return ($1);
}

# Log out the global $ua object or die with an error.
sub logout {
    print "Logging out...\n";
    my $response = $ua->post($qualysurl . '/api/2.0/fo/session/', ['action' => 'logout']);
    print "DEBUG - Logout response:\n" . $response->content if ($debug);
    die("Logout failed with info:\n".Dumper($response)) unless ($response->is_success);
}

# Log out the global $ua object (so as not to leave a dangling
# FO session), print the passed message, and die.
sub quit {
    my($msg, @junk) = @_;
    logout();
    die($msg);
}

# Get a listing all all unscanned hosts IPs
sub get_hosts {
    my $nextBlock = shift;
    my @idList = ();
    print "Getting a list of all hosts not since $startdate";
    print " (with starting ID $nextBlock)" if ($nextBlock);
    print "...\n";
    my $r;
    if ($nextBlock) {
    $r = POST($qualysurl . '/api/2.0/fo/asset/host/',
                 ['action' => 'list',
                  'details' => 'All',
                  'no_vm_scan_since' => $startdate,
                  'id_min' => $nextBlock,
                 ]);
    } else {
    $r = POST($qualysurl . '/api/2.0/fo/asset/host/',
                 ['action' => 'list',
                  'details' => 'All',
                  'no_vm_scan_since' => $startdate,
                 ]);    
    }
    my $response = $ua->request($r);
    if ($response->is_success) {
      # Grab the XML for parsing
      my $xmlRef = XMLin($response->content);
      
      # Do we have a warning that there are more hosts?
      if ($xmlRef->{RESPONSE}->{WARNING}->{URL} =~ /id_min=\d*/i) {
        # Sure do, remember for next time
        $xmlRef->{RESPONSE}->{WARNING}->{URL} =~ /id_min=(\d*).*/i;
        $nextBlock = $1;
        print "More than 1000 hosts returned...next minimum ID is $nextBlock\n";
      } else {
        $nextBlock = 0;
      }
      # Turn into a host IP list
      if (ref($xmlRef->{RESPONSE}->{HOST_LIST}->{HOST}) eq 'ARRAY') {
        foreach my $hostEntry (@{$xmlRef->{RESPONSE}->{HOST_LIST}->{HOST}}) {
          print "IP: $hostEntry->{IP}\t\tLast scan: $hostEntry->{LAST_VULN_SCAN_DATETIME}\n";
          push(@idList, $hostEntry->{ID});
        }
      } else {
        # Just one?
        print "IP: $xmlRef->{RESPONSE}->{HOST_LIST}->{HOST}->{IP}\t\tLast scan: $xmlRef->{RESPONSE}->{HOST_LIST}->{HOST}->{LAST_VULN_SCAN_DATETIME}\n";
        push(@idList, $xmlRef->{RESPONSE}->{HOST_LIST}->{HOST}->{ID});
        $nextBlock = 0;
      }
    } else {
      print "ERROR listing:  $response->content";
      $nextBlock = 0;
    }
    
    # Lastly, return the ID list
    my $retList = join(',', @idList);
    return ($retList, $nextBlock);
}


# Use asset/hosts purge capabilities to purge inactive hosts.
sub purge_hosts {
    my $idList = shift;
    print "Purging hosts not scanned since $startdate...\n";
    my $r = POST($qualysurl . '/api/2.0/fo/asset/host/',
                 ['action' => 'purge',
                  'no_vm_scan_since' => $startdate,
                  'ids' => $idList
                 ]);
    my $response = $ua->request($r);
    if ($response->is_success) {
      print "Purge successful.";
    } else {
      print "ERROR purging:  $response->content";
    }
    print "DEBUG - purge response:\n" . Dumper($response->content) if ($debug);
}

# Calculate a date in the future *without* requiring a module like Date::Calc
sub getnewdate {
  my $delta = shift;
  my $time = time();
  my $future_time = $time - ($delta * 24 * 60 *60);
  my ($fsecond, $fminute, $fhour, $fday, $fmonth, $fyear, $fdayOfWeek, $fdayOfYear, $fdaylightSavings) = localtime($future_time);

  # Must fix up month (zero-based) and year (offset from 1900)
  $fmonth += 1;
  $fyear += 1900;

  my $datestr = sprintf('%04d-%02d-%02d',$fyear,$fmonth,$fday);
  return $datestr;
}
