#!/usr/local/bin/perl -w
#@(#)$Revision: 1.4 $


use LWP::UserAgent;
use Config::Simple;
use HTTP::Request;
require XML::Twig;

my $request;	        # HTTP request handle
my $result;		# HTTP response handle
my $server;		# QualysGuard server's FQDN hostname
my $url;		# API access URL
my $xml;		# Twig object handle
my $username1="";
my $password1="";
my $target_ip_file="";
my $tracking_method="";
my $owner="";
my $location="";
my $function="";
my $asset_tag="";
my $comment="";
my $query="";

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

my $conffile = ($ARGV[0] || 'addassetip.conf');
my $conf = new Config::Simple($conffile);

my $missing_elements;
$missing_elements  = "username "  if (! $conf->param('username'));
$missing_elements .= "password "  if (! $conf->param('password'));
$missing_elements .= "targetipfile " if (! $conf->param('targetipfile'));

die "required element(s) missing from conf file: " . $missing_elements if ($missing_elements);

if ($conf->param('server')) {
	$server = $conf->param('server');
} else {
	$server = "qualysapi.qualys.com";
}

if ($conf->param('username')) {
	 $username1 = $conf->param('username');
}

if ($conf->param('password')) {
	 $password1 = $conf->param('password');
}

if ($conf->param('targetipfile')) {
	 $target_ip_file = $conf->param('targetipfile');
}

print "username=$username1\npassword=$password1\ntarget_file=$target_ip_file\n";

unless (open(FILE, $target_ip_file))
{
die ("cannot open IP input file=$target_ip_file\n");
}
@input = <FILE>;
my $variable="";
my @newarray;
my $i;
my $k;
my $string="";
for ($i=0;$i<scalar @input;$i++){
	my $j=$i+1;
	if ( $input[$i] =~ /((\d+\.\d+\.\d+\.\d+)\-(\d+\.\d+\.\d+\.\d+))/)
	{
		($variable) = ( $input[$i] =~ /((\d+\.\d+\.\d+\.\d+)\-(\d+\.\d+\.\d+\.\d+))/);
		push(@newarray,$variable);
	}
	elsif ( $input[$i] =~ /(\d+\.\d+\.\d+\.\d+)/)
	{
		($variable) = ( $input[$i] =~ /(\d+\.\d+\.\d+\.\d+)/);
		push(@newarray,$variable);
	}
	else
	{
		print "IP pattern not found in the line $j of the input file\n";
	}
}
for ($k=0;$k<scalar @newarray;$k++){
	$string .="$newarray[$k],";
	if ($k== $#newarray){
		$string=substr($string, 0, -1);}
	}
	$query .= "&host_ips=$string";
			
	if ($conf->param('tracking_method') && $conf->param('tracking_method') ne ""){
		$tracking_method = $conf->param('tracking_method');
		$query .= "&tracking_method=$tracking_method";
		
	}if ($conf->param('owner') && $conf->param('owner') ne ""){
		$owner = $conf->param('owner');
		$query .= "&owner=$owner";
		
	}if ($conf->param('location') && $conf->param('location') ne ""){
		$location = $conf->param('location');
		$query .= "&ud1=$location";
		
	}if ($conf->param('function') && $conf->param('function') ne ""){
		$function = $conf->param('function');
		$query .= "&ud2=$function";
		
	}if ($conf->param('asset_tag') && $conf->param('asset_tag') ne ""){
		$asset_tag = $conf->param('asset_tag');
		$query .= "&ud3=$asset_tag";
		
	}if ($conf->param('comment') && $conf->param('comment') ne ""){
		$comment = $conf->param('comment');
		$query .= "&comment=$comment";
	}
print "query=$query\n";	

 my $show_url = 0;
 
 # XML::Twig is a handy way to process an XML document. We use it to attach
 # various handlers, which are triggered whenever related tags are found
 # in the XML document. We also attach an error() handler, which is
 # triggered whenever Twig finds any errors.  The generic_return() 
 #handler covers the case where a
 # <GENERIC_RETURN> element is encountered.
 
 $url  = "https://$server/msp/asset_ip.php?action=add$query";
	
			$xml = new XML::Twig(
			TwigHandlers => {
				ERROR             => \&error,
				GENERIC_RETURN    => \&generic_return,
			},
	);
	

# Create an instance of the authentication user agent

    my $ua  = LWP::UserAgent->new();
    
    $request = new HTTP::Request GET => $url;
    
    $request->authorization_basic($username1, $password1);

    #$response = $ua->request($request);


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



