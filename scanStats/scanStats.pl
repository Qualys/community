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
my ($username, $password, $help, $proxy, $proxy_username, $proxy_password, $debug, $server_url, $usefile, $fileUsed, %agMap, %taskInfo, %scannerLoad, %jobInfo);

# Get command line options
GetOptions('username=s'       => \$username,
           'password=s'       => \$password,
           'proxy=s'          => \$proxy,
           'proxy_username=s' => \$proxy_username,
           'proxy_password=s' => \$proxy_password,
           'debug'            => \$debug,
           'help'             => \$help,
           'usefile=s'        => \$usefile,
           'serverurl=s'      => \$server_url);

# Does the user want help?
usage() if ($help);

# Default to US - sorry, Europeans
$server_url = 'https://qualysapi.qualys.com' unless ($server_url);

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

# Set up default file name
$fileUsed = 1 if ($usefile);
$usefile = 'scanStats.xml' unless ($usefile);

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
$ua->ssl_opts( verify_hostnames => 0 ); 
$ua->default_header('X-Requested-With' => $agent_string);
$ua->cookie_jar({});
my $cookiejar = HTTP::Cookies->new();

#---------------------------------------
#
# Main script starts here
#
#---------------------------------------

# Do the login if needed
my $sessionCookie;
$sessionCookie = login() unless (-e $usefile && $fileUsed);

# First, get AG list
&getAGInfo() unless (-e $usefile && $fileUsed);

# Now create the map
&makeAGMap();

# Next, get scheduled tasks
&getTasks() unless (-e $usefile && $fileUsed);

# Now parse them for all sorts of goodies.
&parseTasks();

# Now quickly print the report on AGs
# $agMap{$title} = {ID => $id, IPS => $ipCount, DEFAULT => $defScanner, SCANNERS => $scannerList, NETBLOCKS => $netblockCount, AVGSCAN => $avg, ALIVEIPS => $liveHosts };

print "AG,ID,IPS,ALIVEIPS,AVGSCAN,NETBLOCKS,DEFAULT,SCANNERS\n";
foreach my $ag (sort keys %agMap) {
	print '"' . $ag . '",'. "$agMap{$ag}->{ID},$agMap{$ag}->{IPS},$agMap{$ag}->{ALIVEIPS},$agMap{$ag}->{AVGSCAN},$agMap{$ag}->{NETBLOCKS},$agMap{$ag}->{DEFAULT},";
	print '"';
	my $salist = '';
	foreach my $sa (@{$agMap{$ag}->{SCANNERS}}) {
		$salist .= "$sa,";
	}
	chop($salist);
	print "$salist";
	print '"'."\n";
}

print "\nSCANNER,MONTHLYIPS,MONTHLYALIVEIPS\n";
foreach my $sa (sort keys %scannerLoad) {
	print "$sa,$scannerLoad{$sa}{TOTAL},$scannerLoad{$sa}{ALIVE}\n";
}


print "\nJOB,IPS,ALIVEIPS,NETBLOCKS,MULTIPLIER,SCANNERS\n";
foreach my $job (sort keys %jobInfo) {
	print qq!"$job",$jobInfo{$job}->{IPS},$jobInfo{$job}->{ALIVEIPS},$jobInfo{$job}->{NETBLOCKS},$jobInfo{$job}->{MULTIPLIER},"$jobInfo{$job}->{SCANNER}"\n!;
}

# Logout and quit.
logout() if ($sessionCookie);

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
    --debug=y                    Outputs additional information
    --usefile=SOMEFILE           Don't download, but use the provided filename instead
    --help                       Provide usage information (what you are reading)

$appname will download download scheduled tasks and look for sub-optimal scanner loads.

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

# Get all scheduled tasks (v1 API)
sub getTasks {
    print "Getting task list to file $usefile...\n";
    my $url = "$qualysurl/msp/scheduled_scans.php?&type=scan&active=yes";
    print "URL: $url\n" if ($debug);
  
	# Add some credentials
	my $req = HTTP::Request->new(GET => $url);
	$req->authorization_basic($username, $password);
	my $res = $ua->request($req);  
	if (! $res->is_success){
	  my $error   = $res->status_line;
	  print "Failed to fetch task list with error: $error";
	}
	# Save the results to a file
	open(MYFILE, ">$usefile");
	binmode(MYFILE);
	print MYFILE $res->content;
	close(MYFILE);

}

# Get all asset group sizes and scanners
sub getAGInfo {
	my $url = "$qualysurl/msp/asset_group_list.php";
	my $agFile = "$usefile.aglist";
    print "URL: $url\n" if ($debug);
  
	# Add some credentials
	my $req = HTTP::Request->new(GET => $url);
	$req->authorization_basic($username, $password);
	my $res = $ua->request($req);  
	if (! $res->is_success){
	  my $error   = $res->status_line;
	  print "Failed to fetch asset group list with error: $error";
	}
	# Save the results to a file
	open(MYFILE, ">$agFile");
	binmode(MYFILE);
	print MYFILE $res->content;
	close(MYFILE);
}

# Parse the info from the AG list	
sub makeAGMap {
	my $agFile = "$usefile.aglist";
		
    # Grab the XML for parsing and free up memory
    my $xmlRef = XMLin($agFile);
    
    # Now loop through each AG and build the map
    foreach my $agEntry (@{$xmlRef->{ASSET_GROUP}}) {
    	my $id = $agEntry->{ID};
    	my $title  = $agEntry->{TITLE};
    	
		# Must have one or more scanIPs
		my $ipCount = 0;
		my $netblockCount = 0;
		if (ref($agEntry->{SCANIPS}->{IP}) eq 'ARRAY') {
			foreach my $ipEntry (@{$agEntry->{SCANIPS}->{IP}}) {
				my ($ips, $nets) = &countTargets($ipEntry);
				$ipCount += $ips;
				$netblockCount += $nets;
			}
		} else {
			my $ipEntry = $agEntry->{SCANIPS}->{IP};
			my ($ips, $nets) = &countTargets($ipEntry);
			$ipCount += $ips;
			$netblockCount += $nets;
		}
		
		# Get scanner list and find default
		my $defScanner = '';
		my $scannerList = ();
		if (ref($agEntry->{SCANNER_APPLIANCES}->{SCANNER_APPLIANCE}) eq 'HASH') {
			# Only one
			$defScanner = $agEntry->{SCANNER_APPLIANCES}->{SCANNER_APPLIANCE}->{SCANNER_APPLIANCE_NAME};
			push(@{$scannerList}, $defScanner);
		} elsif (ref($agEntry->{SCANNER_APPLIANCES}->{SCANNER_APPLIANCE}) eq 'ARRAY') {
			# Loop through and find the default
			foreach my $saEntry (@{$agEntry->{SCANNER_APPLIANCES}->{SCANNER_APPLIANCE}}) {
				$defScanner = $saEntry->{SCANNER_APPLIANCE_NAME} if ($saEntry->{asset_group_default} == 1);
				push(@{$scannerList}, $saEntry->{SCANNER_APPLIANCE_NAME});
			}
		} else {
			# No scanners
			$defScanner = 'none';
			push(@{$scannerList}, 'none');
		}

		# Get the # of hosts and time to scan
		my ($avg, $liveHosts) = &getTimes($title,$id);

		# Shove it into the hash		
		$agMap{$title} = {ID => $id, IPS => $ipCount, DEFAULT => $defScanner, SCANNERS => $scannerList, NETBLOCKS => $netblockCount, AVGSCAN => $avg, ALIVEIPS => $liveHosts };
		
		print "$title: $id, $ipCount ($liveHosts), $avg seconds, $netblockCount, $defScanner, @{$scannerList}\n" if ($debug);
    }
    
}	

# Look through the scheduled tasks and assign workloads to each
# Tasks XML looks like this:
#
#		<SCAN active="yes" ref="292084">
#		  <TITLE><![CDATA[Incremental Vulnerability Scan]]></TITLE>
#		  <TARGETS><![CDATA[10.10.10.220,10.10.24.78-10.10.24.79,10.10.24.112,10.10.24.133,10.10.25.69,10.10.25.87-10.10.25.88,10.10.26.234,10.10.32.91-10.10.32.92,10.10.32.95, 10.10.26.154,10.10.26.166,10.10.30.153-10.10.30.154, 10.10.24.203,10.10.31.211,10.10.32.85-10.10.32.87,10.10.32.90, 10.10.24.108,10.10.24.200-10.10.24.201, 10.10.30.129-10.10.30.130, 10.10.10.34,10.10.10.127, 10.10.30.210-10.10.30.212, 10.10.10.143, 10.10.10.145,10.10.10.152, 10.10.26.132,10.10.30.5, 10.10.30.7, 10.10.25.41,10.10.30.70, 10.10.25.43,10.10.25.71, 10.10.25.45,10.10.26.208-10.10.26.209,10.10.31.37, 10.10.29.121, 10.10.26.86,10.10.30.36,10.10.31.42, 10.10.24.35,10.10.26.91,10.10.30.37, 10.10.24.125,10.10.30.38,10.10.31.31, 10.10.31.128-10.10.31.129, 10.10.31.59,10.10.31.61, 10.10.31.58,10.10.31.62, 10.10.31.104,10.10.31.107, 10.10.31.102,10.10.31.106, 10.10.25.158, 10.10.25.159,10.10.30.42, 10.10.24.67, 10.10.24.68, 10.10.24.69, 10.10.24.12-10.10.24.13, 10.20.30.56, 10.20.30.58, 10.20.30.59, 10.10.24.93,10.10.25.26,10.10.25.70,10.10.25.183,10.10.26.110-10.10.26.111,10.10.32.93]]></TARGETS>
#		  <SCHEDULE>
#		    <WEEKLY frequency_weeks="1" weekdays="6"/>
#		    <START_DATE_UTC>2011-07-30T07:00:00</START_DATE_UTC>
#		  <START_HOUR>0</START_HOUR>
#		  <START_MINUTE>0</START_MINUTE>
#		  <TIME_ZONE>
#		    <TIME_ZONE_CODE>US-CA</TIME_ZONE_CODE>
#		    <TIME_ZONE_DETAILS><![CDATA[(GMT-0800) United States (California): Los Angeles, San Francisco, San Diego, Sacramento]]></TIME_ZONE_DETAILS>
#		  </TIME_ZONE>
#		  <DST_SELECTED>1</DST_SELECTED>
#		  </SCHEDULE>
#		  <NEXTLAUNCH_UTC>2012-03-31T07:00:00</NEXTLAUNCH_UTC>
#		  <DEFAULT_SCANNER>0</DEFAULT_SCANNER>
#		  <ISCANNER_NAME>All Scanners in AG</ISCANNER_NAME>
#		  <OPTION>Authenticated Scan v.1</OPTION>
#		  <TYPE>SCAN</TYPE>
#		  <ASSET_GROUPS>
#		    <ASSET_GROUP>
#		      <ASSET_GROUP_TITLE><![CDATA[Qualys - QA Lab - Windows Server 2003]]></ASSET_GROUP_TITLE>
#		    </ASSET_GROUP>
#		    <ASSET_GROUP>
#		      <ASSET_GROUP_TITLE><![CDATA[Qualys - QA Lab - Windows XP]]></ASSET_GROUP_TITLE>
#		    </ASSET_GROUP>
#		  </ASSET_GROUPS>
#		  <EXCLUDE_IP_PER_SCAN>192.168.1.1-192.168.1.128</EXCLUDE_IP_PER_SCAN>
#		  <OPTION_PROFILE>
#		    <OPTION_PROFILE_TITLE option_profile_default="0"><![CDATA[Authenticated Scan v.1]]></OPTION_PROFILE_TITLE>
#		  </OPTION_PROFILE>
#		</SCAN>
#

sub parseTasks {
    # Grab the XML for parsing
    my $xmlRef = XMLin($usefile);
    
    foreach my $scanEntry (@{$xmlRef->{SCAN}}) {
		my $title = $scanEntry->{TITLE};

		# Skip inactives
		next if ($scanEntry->{active} =~ /no/i);
	
		print "Job: $title\n" if ($debug);
		
		# OK, first let's get the total number of targets that we have:
		my $targetList = $scanEntry->{TARGETS};
		
		# Get the scanner name
		my $scannerName = $scanEntry->{ISCANNER_NAME};

		# Don't bother for tag scans (which don't have target lists and aren't supported right now)
		unless ($targetList) {
			print "Skipping Tag Scan $title\n" if ($debug);
			next;
		}
		
		# Get the schedule and multiply for the month.  Very primative right now.
		my $freq = $scanEntry->{SCHEDULE};
		my $multiplier = 1;
		
		# Are we daily?
		if ($freq->{DAILY}) {
			my $days = $freq->{DAILY}->{frequency_days};
			# Multiplier equals the number of times each month we'll do this (30 days / x, where = x number of days between scans)
			$multiplier = int(30/$days);
		} elsif ($freq->{WEEKLY}) {
			# We're weekly
			my $weeks = $freq->{WEEKLY}->{frequency_weeks};
			# Days per week is a string like "1,2,4"
			my @days = split(/,/, $freq->{WEEKLY}->{weekdays});
			my $dayCount = $#days + 1;
			# How many weeks each month do we run?
			$multiplier = int (4/$weeks);
			# Multiply by number of days each week
			$multiplier = $multiplier * $dayCount;
		} 


		# The scanner tells the story.  There are three options here:
		#
		# 1 - A single scanner:    This makes life very easy, as it is just doing the targets.
		# 2 - Default scanner:     Not so bad; just count the IPs in each asset group targeted, and assign them to the scanner.
		# 3 - All Scanners in AG:  Time to work; count the IPs in each asset group and divvy them up amound the scanners.
		# 

		# First and foremost let's get the scanners.  If we only have one scanner then determining the load is easy; 
		# if we have multiple scanners then it gets to be a little more work.
		my $SINGLE_SCANNER = 1;
		my $DEFAULT_SCANNER = 2;
		my $BALANCE_SCANNERS = 3;
		
		# Default to single scanner unless the task tells us otherwise
		my $scannerLookup = $SINGLE_SCANNER;
		
		# Are we doing default scanner?
		$scannerLookup = $DEFAULT_SCANNER if ($scanEntry->{DEFAULT_SCANNER} == 1);
	
		# All scanners in Asset Group?
		$scannerLookup = $BALANCE_SCANNERS if ($scannerName =~ /All Scanners in AG/i);

		# Get AG list for job		
		my @agList = ();
		if (ref($scanEntry->{ASSET_GROUPS}->{ASSET_GROUP}) eq 'ARRAY') {
			foreach my $agEntry (@{$scanEntry->{ASSET_GROUPS}->{ASSET_GROUP}}) {
				push(@agList, $agEntry->{ASSET_GROUP_TITLE});
			}
		} elsif (ref($scanEntry->{ASSET_GROUPS}->{ASSET_GROUP}) eq 'HASH') {
			push(@agList, $scanEntry->{ASSET_GROUPS}->{ASSET_GROUP}->{ASSET_GROUP_TITLE});
		}

		# Add alive IPs to load
		my $aliveIPs = 0;
		foreach my $ag (@agList) {
			$aliveIPs += $agMap{$ag}->{ALIVEIPS};
		}

		# OK, figure out how the scan is done.
		my $ipCount = 0;
		my $netBlocks = 0;
		if ($scannerLookup == $SINGLE_SCANNER) {
			
			# Easy peasy - case 1 above - just count targets and assign to this scanner.
			($ipCount,$netBlocks) = &countTargets($targetList);
			
			# Add to scanner load
			$scannerLoad{$scannerName}{TOTAL} += ($ipCount * $multiplier);
			$scannerLoad{$scannerName}{ALIVE} += ($aliveIPs * $multiplier);
			
			print "Single Scanner: $scannerName - $ipCount\n" if ($debug);
			
			# Add to map
			$jobInfo{$title} = { SCANNER => $scannerName, IPS => $ipCount, MULTIPLIER => $multiplier, ALIVEIPS => $aliveIPs, NETBLOCKS => $netBlocks };
			
		} elsif (($scannerLookup == $DEFAULT_SCANNER) || ($scannerLookup == $BALANCE_SCANNERS)) {
			
			my $allScanners = '';

			# Now assign the count of each AG 
			foreach my $agEntry (@agList) {
				
				# Add to just one scanner?
				if ($scannerLookup == $DEFAULT_SCANNER) {

					# Add to scanner load
					$scannerLoad{$agMap{$agEntry}->{DEFAULT}}{TOTAL} += ($agMap{$agEntry}->{IPS} * $multiplier);
					
					# Add real load
					$scannerLoad{$agMap{$agEntry}->{DEFAULT}}{ALIVE} += ($agMap{$agEntry}->{ALIVEIPS} * $multiplier);
					
					print "Default Scanner: $agMap{$agEntry}->{DEFAULT} - $agMap{$agEntry}->{IPS} with multiplier of $multiplier\n" if ($debug);

					$ipCount += $agMap{$agEntry}->{IPS} * $multiplier;
					$netBlocks += $agMap{$agEntry}->{NETBLOCKS};
					
					# Add to scanner listing
					$allScanners .= "$agMap{$agEntry}->{DEFAULT},";
					
					
				} else {
					
					# Get the number of scanners
					my $scannerList = $agMap{$agEntry}->{SCANNERS};
					my $scannerCount = $#{$scannerList} + 1;
					my $balancedIPs = int($agMap{$agEntry}->{IPS} / $scannerCount);
					my $balancedAlive = int($agMap{$agEntry}->{ALIVEIPS} / $scannerCount);

					$ipCount += $agMap{$agEntry}->{IPS} * $multiplier;
					$netBlocks += $agMap{$agEntry}->{NETBLOCKS};
					
					# Short circuit here:  if targets are less than scanners then just assign all to the first
					# (althought it would really look for the least loaded scanner in JOBD, and wouldn't hand out
					# less than a slice)
					unless ($balancedIPs) {
						$scannerLoad{$agMap{$agEntry}->{DEFAULT}}{TOTAL} += ($agMap{$agEntry}->{IPS} * $multiplier);
						$scannerLoad{$agMap{$agEntry}->{DEFAULT}}{ALIVE} += ($agMap{$agEntry}->{ALIVEIPS} * $multiplier);						
						next;
					} 
						
					# Enough to balance
					foreach my $sa (@$scannerList) {
						
						# Add to load
						$scannerLoad{$sa}{TOTAL} += ($balancedIPs * $multiplier);
						$scannerLoad{$sa}{ALIVE} += ($balancedAlive * $multiplier);
						
						print "$title/$agEntry: Load balance: $sa - $balancedIPs\n" if ($debug);
						
						# Add to scanner listing
						$allScanners .= "$sa,";
					
					}
					
				}
				
			}
			
			# Add job info
			chop($allScanners);
			$jobInfo{$title} = { SCANNER => $allScanners, IPS => $ipCount, MULTIPLIER => $multiplier, ALIVEIPS => $aliveIPs, NETBLOCKS => $netBlocks };
			
		}
    }
}


# Get the average time for an asset group
sub getTimes {
	my $r;
	my $assetGroup = shift;
	my $id = shift;

	# Default to one month ago
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
	# Fix year
	$year += 1900;
	# Month is already zero-based; wrap to december ("12") if it's January
	$mon = 12 if ($mon == 0);
	
	# Zero pad month and day
	$mon = '0'.$mon if ($mon < 10);
	$mday = '0'.$mday if ($mday <10);
	my $scandate = $year.'-'.$mon.'-'.$mday;

	# Use files
	unless (-e "$usefile.$id" && $fileUsed) {
		$r = POST($qualysurl . '/api/2.0/fo/asset/host/vm/detection/',
			['action' => 'list',
			 'ag_titles' => $assetGroup,
			 'show_igs' => '1',
			 'qids' => '45038',
			 'truncation_limit' => '0',
			 'vm_scan_since' => $scandate,
			]);    
		my $response = $ua->request($r);
		open(MYFILE, ">$usefile.$id");
		binmode(MYFILE);
		print MYFILE $response->content;
		close(MYFILE);
	}


    # Grab the XML for parsing
    my $xmlRef = XMLin("$usefile.$id");
    my $total = 0;
    my $count = 0;
    my $hostCount = 0;
    
	# Do we have a single result
	if (ref($xmlRef->{RESPONSE}->{HOST_LIST}->{HOST}) eq 'ARRAY') {
	    # Loop throught the results
	    foreach my $hostEntry (@{$xmlRef->{RESPONSE}->{HOST_LIST}->{HOST}}) {
			my $timeEntry = $hostEntry->{DETECTION_LIST}->{DETECTION}->{RESULTS};
			$timeEntry =~ m/ation: (\d*) sec/;
			
			# Add an entry for averages
			$total += $1;
			$count++;
			$hostCount++;	  
	    }
	} elsif ($xmlRef->{RESPONSE}->{HOST_LIST}->{HOST}) {
		my $timeEntry = $xmlRef->{RESPONSE}->{HOST_LIST}->{HOST}->{DETECTION_LIST}->{DETECTION}->{RESULTS};
		$timeEntry =~ m/ation: (\d*) sec/;
		
		# Add an entry for averages
		$total += $1;
		$count++;
		$hostCount++;	  
	}		

    # Don't bother if nothing found
    unless ($count) {
    	print "$assetGroup has no time results and $hostCount hosts\n" if ($debug);
    	return (0,$hostCount);
    }
    
    # Now calculate average and STD DEV
    my $avg = int($total/$count);

	print "$assetGroup has $hostCount live hosts and $avg average scan time\n" if ($debug);
    
    # Return stats
	return ($avg,$hostCount);

}

# Count IPs in target list
sub countTargets {
	my $targetList = shift;

	# OK, first let's get the total number of targets that we have:
	# Clean up any spaces
	$targetList =~ s/ //g;
	# Break into an array
	my @targets = split(/,/, $targetList);
	my $ipCount = 0;
	my $netCount = 0;
	foreach my $ipEntry (@targets) {
		# Add to netblocks
		$netCount++;
		# Is this a range?
		if ($ipEntry =~ /-/) {
			# Yes, get start value and end value
			my ($startIP,$endIP) = split(/-/, $ipEntry);
			# Convert IPs into numbers and get counts
			$ipCount += (&ipToNum($endIP) - &ipToNum($startIP)) + 1;  # Add one for fencepost
		} else {
			# Nope, just a single IP
			$ipCount++;
		}
	}

	# Done!
	return ($ipCount, $netCount);
}


# Utility function to turn IP address into a number
sub ipToNum {
	my $ip = shift;
	my $num = 0;

 	if ( $ip =~ /^\d+\.\d+\.\d+\.\d+/ ) {
 		$ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
 		$num = (16777216*$1)+(65536*$2)+(256*$3)+$4;
 	}
 	
 	return $num;
}






















