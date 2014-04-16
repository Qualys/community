#!/usr/bin/perl

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
my $version = '1.0.0';
my ($username, $password, $startdate, $format, $path, $help, $aglist, $usefile, $details, $skip,
    $proxy, $proxy_username, $proxy_password, $debug, $file, $server_url) = ('', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '');

# Get command line options
GetOptions('username=s'       => \$username,
           'password=s'       => \$password,
           'proxy=s'          => \$proxy,
           'proxy_username=s' => \$proxy_username,
           'proxy_password=s' => \$proxy_password,
           'debug'            => \$debug,
           'help'             => \$help,
           'ag=s'             => \$aglist,
           'details'          => \$details,
           'usefile'          => \$usefile,
           'skip=s'           => \$skip,         
           'serverurl=s'      => \$server_url);

# Does the user want help?
usage() if ($help);

# Make sure we have all the arguments.
my $msg = '';
my $errStr = 'ERROR - Missing argument';
$msg .= 'username,' unless ($username);
$msg .= 'password,' unless ($password);
$msg .= 'serverurl,' unless ($server_url);
# Get rid of a trailing comma for neatness
chop($msg);

# Make message plural or not
$errStr .= 's' if ($msg =~ /,/);
usage("$errStr: $msg") if ($msg);

# Set up URL
my $qualysurl = $server_url;

# Set default AG
$aglist = 'All' unless ($aglist);

# Get list of skips
my @skips;
@skips = split(/,/, $skip);

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
my $sessionCookie;
$sessionCookie = login() unless ($usefile);

# Get the IGs
&getSoftware();

# Write them
&listSoftware();

# Logout and quit.
logout() if ($sessionCookie);

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
    --serverurl=https://SOMEURL  Platform server url for launching reports

  Optional Arguments:

    --proxy=http://SOMEURL       HTTPS proxy URL
    --proxy_username=SOMEUSER    HTTPS proxy USERNAME
    --proxy_password=SOMEPASS    HTTPS proxy PASSWORD
    --debug=y                    Outputs additional information
    --ag=SOMEAGS                 Asset groups to get times for; if unspecified it will get All
    --details                    Provide details on hosts with installed software
    --skip=SOMELIST              A comma-separated list of patterns to skip (i.e. skip=KB,{.*}
                                   will skip anything with "KB" or {[anything]})
    --help                       Provide usage information (what you are reading)

$appname will get all the installed software found in an environment (using QIDs 90235 and 105319).

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
sub getSoftware {
    my $r;
    
    # Skip if we should use the file that exists
    return if (($usefile) && (-e 'timelist.xml'));
    
    $r = POST($qualysurl . '/api/2.0/fo/asset/host/vm/detection/',
                 ['action' => 'list',
                  'ag_titles' => $aglist,
                  'show_igs' => '1',
                  'qids' => '90235,105319',
                  'truncation_limit' => '0',
                 ]);    
  my $response = $ua->request($r);
  open(MYFILE, ">softwarelist.xml");
  binmode(MYFILE);
  print MYFILE $response->content;
  close(MYFILE);
      
}

# Routine to spit out CSV
sub listSoftware
{

    # Grab the XML for parsing
    my $xmlRef = XMLin('softwarelist.xml');
    my %softwareHash = ();
        
    # Loop throught the results
    foreach my $hostEntry (@{$xmlRef->{RESPONSE}->{HOST_LIST}->{HOST}}) {
      my $hostIP = $hostEntry->{IP};
      if (ref($hostEntry->{DETECTION_LIST}->{DETECTION}) eq 'ARRAY') {
	      foreach my $listEntry (@{$hostEntry->{DETECTION_LIST}->{DETECTION}}) {
	    	my @results = split("\n",$listEntry->{RESULTS});
	    	foreach my $item (@results) {
			  my ($garbage1, $name, $garbage2, $displayname, $garbage3, $version) = split("\t", $item);
			  # Do we skip?
			  if ($skip) {
			  	my $skipit = 0;
			  	foreach my $pat (@skips) {
			  		$skipit = 1 if $displayname =~ /$pat/ig;
			  		# Don't bother keep going if matched
			  		last if ($skipit);
			  	}
			  	# Skip if done
			  	next if ($skipit);
			  }
			  $softwareHash{$displayname}{COUNT} += 1;
			  push(@{$softwareHash{$displayname}{HOSTS}}, "$hostIP ($version)");
	    	}	
	      }
      } else {
      	my $listEntry = $hostEntry->{DETECTION_LIST}->{DETECTION};
	    	my @results = split("\n",$listEntry->{RESULTS});
	    	foreach my $item (@results) {
			  my ($garbage1, $name, $garbage2, $displayname, $garbage3, $version) = split("\t", $item);
			  # Do we skip?
			  if ($skip) {
			  	my $skipit = 0;
			  	foreach my $pat (@skips) {
			  		$skipit = 1 if $displayname =~ /$pat/ig;
			  		# Don't bother keep going if matched
			  		last if ($skipit);
			  	}
			  	# Skip if done
			  	next if ($skipit);
			  }
			  $softwareHash{$displayname}{COUNT} += 1;
			  push(@{$softwareHash{$displayname}{HOSTS}}, "$hostIP ($version)");
	    	}	
	  }
    } 
    
    print "Count\tSoftware\n";
	# Time to print
	foreach my $software (sort keys %softwareHash) {
		print $softwareHash{$software}{COUNT}."\t".$software."\n";
		if ($details) {
			foreach my $entry (@{$softwareHash{$software}{HOSTS}}) {
				print "\t\t$entry\n";
			}
		}
	}
}