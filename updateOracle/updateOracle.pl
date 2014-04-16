#!/usr/bin/perl

=head1 NAME

updateAuth

=head1 SYNOPSIS

This script uses the QualysGuard API to update authentication records.

=head1 DESCRIPTION

See usage() defined at the bottom of this script.

=head1 EXAMPLES

updateAuth.pl --user=foo --password=bar --serverurl=https://qualysapi.qualys.com --updatefile=myfile.txt

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
use File::Basename;
use Data::Dumper;
use XML::Twig;

#---------------------------------------
#
# Globals
#
#---------------------------------------
my $appname = basename($0);
my $version = '1.0.0';
my ($username, $password, $server_url, $help, $proxy, $proxy_username, $proxy_password, $debug, $titlematch, $newuser, $newpass, $idlist, $testonly);

# Get command line options
GetOptions('username=s'       => \$username,
           'password=s'       => \$password,
           'proxy=s'          => \$proxy,
           'proxy_username=s' => \$proxy_username,
           'proxy_password=s' => \$proxy_password,
           'serverurl=s'      => \$server_url,           
           'debug'            => \$debug,
           'help'             => \$help,
           'title=s'          => \$titlematch,
           'idlist=s'         => \$idlist,
           'newuser=s'        => \$newuser,
           'newpass=s'        => \$newpass,
           'test'             => \$testonly,
);

# Does the user want help?
usage() if ($help);

# Make sure we have all the arguments.
my $msg = '';
my $errStr = 'ERROR - Missing argument';
$msg .= 'username,' unless ($username);
$msg .= 'password,' unless ($password);
$msg .= 'updated username or password,' unless ($newpass or $newuser);

# Get rid of a trailing comma for neatness
chop($msg);

# Make message plural or not
$errStr .= 's' if ($msg =~ /,/);
usage("$errStr: $msg") if ($msg);

# Default to US API
$server_url = 'https://qualysapi.qualys.com' unless $server_url;

# Emit starting timestamp
my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
print "$appname starting at: $hour:$min:$sec\n";

# Configure the user agent
$ENV{'HTTPS_PROXY'} = $proxy if ($proxy);
$ENV{'HTTPS_PROXY_USERNAME'} = $proxy_username if ($proxy_username);
$ENV{'HTTPS_PROXY_PASSWORD'} = $proxy_password if ($proxy_password);
$ENV{HTTPS_PKCS12_FILE}     = '';
$ENV{HTTPS_PKCS12_PASSWORD} = '';
my $agent_string = $appname .'$Revision: '.$version.' $';
my $ua = LWP::UserAgent->new('agent'                 => $agent_string,
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

# Login first
&login();

# Do we need to get a list of IDs, or are they supplied?
&listAuth() unless ($idlist);	
print "Updating IDs: $idlist...\n" if ($debug);

# Now update
&updateAuth($idlist);

# Logout
&logout();

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
    --serverurl=https://SOMEURL  Platform server url for launching reports
    --newuser                    Update all selected records with this user ID.  
    							   Either NEWUSER or NEWPASS must be specifed (or both).
    --newpass                    Update all selected records with this password.
    							   Either NEWUSER or NEWPASS must be specifed (or both).

  Optional Arguments:

    --proxy=http://SOMEURL       HTTPS proxy URL
    --proxy_username=SOMEUSER    HTTPS proxy USERNAME
    --proxy_password=SOMEPASS    HTTPS proxy PASSWORD
    --debug                      Outputs additional information
    --title=SOMETITLE            Only display records matching the supplied title
    --idlist=ID_LIST             Update the records in the supplied comma-separated list of IDs 
    --test                       Just display what records would be updated, but don't update
    --help                       Provide usage information (what you are reading)

$appname will update Oracle authentication records.

To update all Oracle records password's to FOO:

  $appname --username=SOMEUSER --password=SOMEPASS --newpass=FOO

To update all Oracle records with "Denver" in the title to use username/password spork/foo:

  $appname --username=SOMEUSER --password=SOMEPASS --newuser=spork --newpass=foo --title=Denver
  


EOF

    exit(1);
}


# Log in the global $ua object and set the QualysSession cookie
# or die with an error.
sub login {
    print "Logging in.\n";
    my $r = POST($server_url . '/api/2.0/fo/session/',
                 ['action' => 'login',
                  'username' => $username,
                  'password' => $password]);
    my $response = $ua->request($r);
    if (!$response->is_success) {
        print "DEBUG - Login response:\n" . $response->content if ($debug);
        die("Login failed!\n");
    }
}

# Log out the global $ua object or die with an error.
sub logout {
    print "Logging out.\n";
    my $response = $ua->post($server_url . '/api/2.0/fo/session/', ['action' => 'logout']);
    if (!$response->is_success) {
        print "DEBUG - Logout response:\n" . $response->content if ($debug);
        die("Logout failed!\n");
    }
}


# Routine to list auth credentials
sub listAuth
{
	my $r;
	if ($titlematch) {
	    $r = POST($server_url . "/api/2.0/fo/auth/oracle/",
			['action' => 'list',
			 'details' => 'None',
			 'title' => $titlematch,
			]);
	} else {
	    $r = POST($server_url . "/api/2.0/fo/auth/oracle/",
            ['action' => 'list',
             'details' => 'None',
            ]);
	}
		
	my $response = $ua->request($r);
    if ($response->is_success) {
           # For real XML parsing we use XML::Simple or XML::Twig,
           # but for checking simple API responses like we can get
           # away with a direct pattern match:
           unless ($response->content =~ /ID_SET/) {
			die "ERROR: No matching IDs\n";
           }	        
		
           # We have a response, let's parse out the IDs
		# Let's create a new twig
		my $twig= new XML::Twig( twig_handlers => { ID => \&rangeInfo, ID_RANGE => \&rangeInfo } );

		# Parse the twig
		$twig->parse( $response->content );
		
		# Finally, chop trailing comma
		chop($idlist);
		
    } else {
      	print "ERROR: ".Dumper($response->content);
    }
}

# Read XML and build list
sub rangeInfo {
  # Passed in the host information
  my ($twig, $id) = @_;

  # Get the ID
  print "Found ID: ".$id->text."\n" if ($debug);
  $idlist .= $id->text.',';
	
}

sub updateAuth
{
	my $ids = shift;
	my $r;
	my %actions = ( action => 'update', ids => $idlist );
	$actions{username} = $newuser if ($newuser);
	$actions{password} = $newpass if ($newpass);
	print qq!Updating to "$newuser:$newpass" for IDs $idlist...\n! if ($debug);
	if ($testonly) {
		print "...but quitting because I'm in TEST mode\n";
		return;
	}
	$r = POST($server_url . "/api/2.0/fo/auth/oracle/", \%actions);
	my $response = $ua->request($r);
    if ($response->is_success) {
           # For real XML parsing we use XML::Simple or XML::Twig,
           # but for checking simple API responses like we can get
           # away with a direct pattern match:
           unless ($response->content =~ /Successfully/) {
			  die "ERROR: ".$response->content;
           }	        
    	
    } else {
      	print "ERROR: ".Dumper($response->content);
    }
  
}
