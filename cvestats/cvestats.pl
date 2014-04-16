#!/usr/bin/perl

=head1 NAME

cvestats

=head1 SYNOPSIS

This script uses the QualysGuard API to download the knowledgebase and figure out coverage stats.

=head1 DESCRIPTION

See usage() defined at the bottom of this script.

=head1 EXAMPLES

cvestats.pl --user=foo --password=bar 

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

# Need this if you have a wonky SAX parser
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

#---------------------------------------
#
# Globals
#
#---------------------------------------
my $appname = basename($0);
my $version = '1.0.0';
my ($username, $password, $path, $help, $dbtable, $dbconnect, $createflag, $usefile,
    $proxy, $proxy_username, $proxy_password, $debug, $server_url) = ('', '', '', '', '', '', '', '', '', '', '', '', '');

# Get command line options
GetOptions('username=s'       => \$username,
           'password=s'       => \$password,
           'proxy=s'          => \$proxy,
           'proxy_username=s' => \$proxy_username,
           'proxy_password=s' => \$proxy_password,
           'debug'            => \$debug,
           'help'             => \$help,
           'usefile'          => \$usefile,
           'serverurl=s'      => \$server_url);

# Does the user want help?
usage() if ($help);

# Make sure we have all the arguments.
my $msg = '';
my $errStr = 'ERROR - Missing argument';
$msg .= 'username,' unless ($username);
$msg .= 'password,' unless ($password);
# Get rid of a trailing comma for neatness
chop($msg);

# Make message plural or not
$errStr .= 's' if ($msg =~ /,/);
usage("$errStr: $msg") if ($msg);

# Set up URL
my $qualysurl = $server_url;

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
my $ua = LWP::UserAgent->new('agent'                => $agent_string,
                             'requests_redirectable' => [],
                             'timeout'               => 900);
$ua->default_header('X-Requested-With' => $agent_string);

#---------------------------------------
#
# Main script starts here
#
#---------------------------------------

# Get the knowledgebase
&getKB();

# Now let's insert into the database
&doStats();

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

  Optional Arguments:

    --proxy=http://SOMEURL       HTTPS proxy URL
    --proxy_username=SOMEUSER    HTTPS proxy USERNAME
    --proxy_password=SOMEPASS    HTTPS proxy PASSWORD
    --debug                      Outputs additional information
    --help                       Provide usage information (what you are reading)

$appname will download the full knowledgebase using the using the QualysGuard API generate coverage stats.

EOF

    exit(1);
}


# Routine to call knowledgebase download
sub getKB
{
		if (-e 'kbdl.xml') {
			if ($usefile) {
					print "*** Using existing file ***\n";
					return;
			}
		}
    my $url = "$server_url/msp/knowledgebase_download.php";
    print "URL: $url\n";
    my $credentialsUrl = 'qualysapi.qualys.com:443';
    $ua->credentials(
        $credentialsUrl,
        'MSP Front Office',
        $username => $password
    );
    
    my $res = $ua->get($url, ':content_file' => 'kbdl.xml');
    if (! $res->is_success){
        my $error   = $res->status_line;
        die "Fetch of knowledgebase failed: $error\n";
    }
   
}

sub doStats
{

    # Grab the XML for parsing
    my $xmlRef = XMLin('kbdl.xml');
    
    # Cache CVE and bugtraq adds for later (so that we have a prepared statement that doesn't change)
    my %cveCount;
    my $vulnCount = 0;

    # Make a counter so that we know how many inserts to do
    foreach my $vulnEntry (@{$xmlRef->{VULN}}) {
      # Add a vuln count
      $vulnCount++ if ($vulnEntry->{QID} > 0);
      # Now insert any CVE items
      if (ref($vulnEntry->{CVE_ID_LIST}->{CVE_ID}) eq 'ARRAY') {
        # We have more than one
        foreach my $cve (@{$vulnEntry->{CVE_ID_LIST}->{CVE_ID}}) {
          $cveCount{$cve->{ID}} = $vulnEntry->{TITLE};
        }
      } elsif ($vulnEntry->{CVE_ID_LIST}) {
        # We have only one CVE
        $cveCount{$vulnEntry->{CVE_ID_LIST}->{CVE_ID}->{ID}} = $vulnEntry->{TITLE} unless ($vulnEntry->{CVE_ID_LIST}->{CVE_ID}->{ID} eq '');
      }
    }

	# Print the results  
  print "Total QIDS: $vulnCount\n";
  print "Total CVE: " . int(keys %cveCount) . "\n";
  foreach my $id (sort keys %cveCount) {
    print qq!"$id","$cveCount{$id}"\n!;
  }
  
}
