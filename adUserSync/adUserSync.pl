#!/usr/bin/perl

use strict;
use Net::LDAP;
use Getopt::Long;
use File::Basename;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTTP::Cookies;
use HTTP::Request::Common;
use XML::Simple;

# Need this if you have a wonky SAX parser
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

my ($aduser, $adpassword, $qguser, $qgpassword, $help, $groupList, %groupHash, $dc, $base, %userHash, %qgUsers, %matchedUsers, %idMap, %adMap, @matchItems, $debug, $qgOnly, $auditOnly);
my $appname = basename($0);
my $version = '1.0.0';
$ENV{HTTPS_PKCS12_FILE}     = '';
$ENV{HTTPS_PKCS12_PASSWORD} = '';
my $agent_string = $appname .'$Revision: '.$version.' $';
my $ua = LWP::UserAgent->new('agent'                => $agent_string,
                             'requests_redirectable' => [],
                             'timeout'               => 900);
$ua->default_header('X-Requested-With' => $agent_string);

# Create QG role hierarchy
# TODO - auditor, POC
my %qgRoleList = ( 'manager' 		=> 4,
				   'unit_manager'	=> 3, 
				   'scanner' 		=> 2, 
				   'reader' 		=> 1,
				   'none'           => -1,
);

# AD attribute for disabled accounts
my $ADS_UF_ACCOUNTDISABLE = 2;

# Get command line options first
GetOptions('aduser=s'         => \$aduser,
           'adpassword=s'     => \$adpassword,
           'qguser=s'         => \$qguser,
           'qgpassword=s'     => \$qgpassword,
           'help'             => \$help,
           'groups=s'         => \$groupList,
           'base=s'           => \$base,
           'qgonlyusers=s',   => \$qgOnly,
           'debug'            => \$debug,
           'auditonly'        => \$auditOnly,
           'dc=s'             => \$dc);

# Does the user want help?
usage() if ($help);

# Make sure we have all the arguments.
my $msg = '';
my $errStr = 'ERROR - Missing argument';
$msg .= 'AD username,' unless ($aduser);
$msg .= 'AD password,' unless ($adpassword);
$msg .= 'QG username,' unless ($qguser);
$msg .= 'QG password,' unless ($qgpassword);
$msg .= 'groups,' unless ($groupList);
# Get rid of a trailing comma for neatness
chop($msg);

# Make message plural or not
$errStr .= 's' if ($msg =~ /,/);
usage("$errStr: $msg") if ($msg);

# Main program here

# Create role to AD group mapping
&createRoleMap();

# Connect to AD and get users
&getADUsers();

# Connect to QG and get users
&getQGUsers();

# Map AD users to QG users
&matchADUsers();

# Get unmatched QG accounts
&getUnmatchedQG();

# Do QG changes
&doQGChanges();

# Done!
exit(0);


# Routines here


sub createRoleMap {

	# Create the hash of AD groups to QG roles
	my @groups = split(',', $groupList);
	foreach my $key (@groups) {
		my ($adGroup, $qualysRole) = split('=',$key);
		$groupHash{$adGroup} = $qualysRole;
	}
}

# Get all the AD users
sub getADUsers {
	
	# Connect and bind to LDAP
	my $ad = Net::LDAP->new($dc);
	$ad->bind($aduser, password=> $adpassword);
	#TODO - error handling if the bind didn't work
	
	# Now get all the users
	my $result = $ad->search( base => $base, filter => '(&(sn=*)(objectClass=person))', a1ttrs => ['sn', 'givenname', 'sAMAccountName', 'memberOf', 'mail', 'userAccountControl']);
	
	# Iterate through all and see if they match the groups
	foreach my $userEntry ($result->entries) {
		
		# Output for debug
#		$userEntry->dump() if ($debug);
		
		my $userAccount = $userEntry->get_value('sAMAccountName');
		my $ref = $userEntry->get_value('memberOf', asref => 1);
		
		# Grab fnln and email while we are here
		my $fnln = $userEntry->get_value('sn') . "/" . $userEntry->get_value('givenname');;
		my $email = $userEntry->get_value('mail');
		$adMap{$userAccount}{FNLN} = $fnln;
		$adMap{$userAccount}{MAIL} = $email;
		$adMap{$userAccount}{DISABLED} = ($userEntry->get_value('userAccountControl') & $ADS_UF_ACCOUNTDISABLE);
		
		# Do they have any group memberships?
		if ($ref) {
			# Yes, see if we have a match.
			foreach my $membership (@$ref) {
				# Get first CN, which is group name
				my ($groupName) = split(',', $membership);
				$groupName =~ s/CN\=//g;
				#print "$userAccount is member of $groupName\n";
				if ($groupHash{$groupName}) {
					# Matched - they get highest privs
					$userHash{$userAccount} = $groupHash{$groupName} if ($qgRoleList{$groupHash{$groupName}} > $qgRoleList{$userHash{$userAccount}});
				}
			}
		}
		# Add as none for later deletion if no memberships
		$userHash{$userAccount} = 'none' unless ($userHash{$userAccount});
	}
}

sub getQGUsers {

	# Call the API and get a user list
	# TODO - unhardcode US SOC
    my $url = "https://qualysapi.qualys.com/msp/user_list.php";
    my $credentialsUrl = 'qualysapi.qualys.com:443';
    $ua->credentials(
        $credentialsUrl,
        'MSP Front Office',
        $qguser => $qgpassword
    );
    
    my $res = $ua->get($url, ':content_file' => 'userlist.xml');
    if (! $res->is_success){
        my $error   = $res->status_line;
        die "Fetch of users failed: $error\n";
    }

    # Grab the XML for parsing
    my $xmlRef = XMLin('userlist.xml');
    
    # Make a counter so that we know how many inserts to do
    foreach my $userEntry (@{$xmlRef->{USER_LIST}->{USER}}) {
      $qgUsers{$userEntry->{USER_LOGIN}} = { 
      	FIRSTNAME => $userEntry->{CONTACT_INFO}->{FIRSTNAME},
      	LASTNAME => $userEntry->{CONTACT_INFO}->{LASTNAME},
      	EMAIL => $userEntry->{CONTACT_INFO}->{EMAIL},
      	ROLE => $userEntry->{USER_ROLE},
      	STATUS => $userEntry->{USER_STATUS},
      	EXTID => $userEntry->{EXTERNAL_ID},
      	MATCH => 'none',
      };      
      # Also map the external ID
      $idMap{EXTID}{$userEntry->{EXTERNAL_ID}} = $userEntry->{USER_LOGIN};	
      # Also map FN/LN
      my $fnln = $userEntry->{CONTACT_INFO}->{FIRSTNAME} . "/" . $userEntry->{CONTACT_INFO}->{LASTNAME};
      $idMap{FNLN}{$fnln} = $userEntry->{USER_LOGIN};	
      # Also map email
      $idMap{MAIL}{$userEntry->{CONTACT_INFO}->{EMAIL}} = $userEntry->{USER_LOGIN};	
    };
    #unlink('userlist.xml');
    
}


# Match AD users to QG users
sub matchADUsers {
	
	# Loop through all AD users
	foreach my $userAccount (sort keys %userHash) {
		# Get roles, FNLN, emai
		my $roles = $userHash{$userAccount};
		my $fnln = $adMap{$userAccount}{FNLN};
		my $email = $adMap{$userAccount}{MAIL};
		my $disabled = $adMap{$userAccount}{DISABLED};
		
	
		# Try to match them up; first by EXTERNAL_ID
		# TODO:  be smarter about this matching, make algorithm options
		my $qgID = '';
		my $matchBy = 'NONE';
		$qgID = $idMap{EXTID}{$userAccount};
		$matchBy = 'EXTID' if ($qgID);
		
		# Next try FNLN if we didn't match
		unless ($qgID) {
			$qgID = $idMap{FNLN}{$adMap{$userAccount}{FNLN}};
			$matchBy = 'FNLN' if ($qgID);	
		}
		
		# Now try email if we didn't match
		unless ($qgID) {
			$qgID = $idMap{MAIL}{$adMap{$userAccount}{MAIL}};
			$matchBy = 'MAIL' if ($qgID);
		}

		# Now get ready to make notes
		my $matchOp = '';
		my $notes = '';
		my $qgrole = '';
		my $extID = '';
		my $qgStatus = '';

		# Did we match?
		if ($qgID) {

			$qgrole = lc($qgUsers{"$qgID"}->{ROLE});
			$extID = lc($qgUsers{"$qgID"}->{EXTID});
			$extID = 'none' unless ($extID);
			$qgStatus = lc($qgUsers{"$qgID"}->{STATUS});
			$qgUsers{"$qgID"}->{MATCH} = $matchBy;


			# Do our roles match?
			if ($roles eq $qgrole) {
				# Yes
				$notes .= "role $roles matches,";
			} else {
				$matchOp = 'UIREQ';
				$notes = "Role mismatch --> AD: $roles QG $qgrole";
				# Push an entry
				push(@matchItems, "$matchOp|$qgID|$notes");

			}

			# Do our external IDs match
			if ($extID eq $userAccount) {
				# Yes
				$notes .= "external ID $extID matches";
				# Push an entry
				push(@matchItems, "GOOD|$userAccount|$notes") if ($notes =~ /matches/i);
				
			} else {
				$matchOp = 'EXTID';
				$notes = "external ID mismatch (QG: $extID, should be $userAccount),";
				# Push an entry
				push(@matchItems, "$matchOp|$qgID|$notes|$userAccount");
			}
			
			# Are we disabled in AD?
			if ($disabled == 2) {
				# Are we disabled in QG?
				if ($qgStatus eq 'active') {
					# No, better do it
					push(@matchItems, "DISABLE|$qgID|$userAccount disabled in AD, $qgID active");
				} elsif ($qgStatus =~ /pending/i) {
					# Pending, this is a problem
					push(@matchItems, "UIREQ|$qgID|disabled in AD, pending activation in QG");					
				}
			}

				
		} else {
			
			# Should they be created?
			if ($roles eq 'none') {
				# Nope, no role
				$matchOp = 'NOOP';
				$notes = "$userAccount has no role in QG";
				# Push an entry
				push(@matchItems, "$matchOp|$userAccount|$notes");
				
			} else {
				# Need to create an account
				$matchOp = 'CREATE';
				$notes = "Could not locate account for $userAccount; create with role $roles";
				# Push an entry
				push(@matchItems, "$matchOp|$userAccount|$notes|$fnln,$email,$roles");
			}

		}
		
	}
	
}


# Get unmatched QG users and deactivate them
sub getUnmatchedQG {
	
	# Don't bother with this at all if --qgonlyusers=ANY
	if (lc($qgOnly) eq 'any') {
		print "Skipping QG sync per --qgonlyusers=ANY on command line...\n";
		return;
	}
	
	# Loop through QG users
	foreach my $qgAccount (sort keys %qgUsers) {

		# Don't worry about unmatched
		next unless ($qgUsers{$qgAccount}->{MATCH} eq 'none');
		
		# Don't worry about exceptions from qgonlyusers on command line
		if ($qgOnly =~ /$qgAccount/i) {
			push(@matchItems, "NOOP|$qgAccount|QG account only allowed per --qgonlyusers option");
			next;
		}
		
		# OK, in QG and not in AD and not granted exception...tee for deactivation
		if (lc($qgUsers{$qgAccount}->{STATUS}) eq 'active') {
			push(@matchItems, "DISABLE|$qgAccount|No matching AD account");
		} elsif ($qgUsers{$qgAccount}->{STATUS} =~ /pending/i) {
			push(@matchItems, "UIREQ|$qgAccount|No matching AD account, pending activation");
		}
	}
	
}


# Do the API calls to make the changes
sub doQGChanges {
	
	my $changeCount = 0;
	
	foreach my $actionItem (@matchItems) {
		
		# Break out the action
		my ($action,$qgID,$notes,$moreInfo) = split(/\|/, $actionItem);
		
		# Big SWITCH here
		if ($action eq 'NOOP') {
			# No operation, nothing to do unless in debug mode.
			print "SKIPPING $actionItem\n" if ($debug);

		} elsif ($action eq 'GOOD') {
			# No operation, nothing to do unless in debug mode.
			print "SKIPPING $actionItem\n" if ($debug);

		} elsif ($action eq 'UIREQ') {
			# Can't be done via API, just log for user
			print "USER ACTION REQUIRED:  $actionItem\n";

		} elsif ($action eq 'DISABLE') {
			# Disable the requested account
			doAPI($action,$qgID);
			print "DISABLING $qgID\n" if ($debug);
			
			
		} elsif ($action eq 'EXTID') {
			# Assign the external ID
			doAPI($action,$qgID,$moreInfo);
			print "ASSIGN EXTID $moreInfo to $qgID\n" if ($debug);


		} elsif ($action eq 'CREATE') {
			# Create new QG user
			doAPI($action,$qgID,$moreInfo);
			print "CREATE for $qgID with attributes $moreInfo\n" if ($debug);
			
		} else {
			# Shouldn't ever be here
			print "SKIPPING unknown action $action\n";
			
		}
		
		$changeCount++;
		
	}
	
	# Summarize what we did.
	print "DONE with $changeCount items\n" if ($debug);
	
}


# Do API call
sub doAPI {
	
	my ($action,$qgID,$moreInfo) = @_;
	my $url = '';
	my $parms = '';
	
	# What to do?
	if ($action eq 'DISABLE') {
		$url = 'https://qualysapi.qualys.com/msp/user.php?action=deactivate&login='.$qgID;
	} elsif ($action eq 'EXTID') {
		$url = 'https://qualysapi.qualys.com/msp/user.php?action=edit&login='.$qgID.'&external_id='.$moreInfo;
	} elsif ($action eq 'CREATE') {
		# Get info out of moreInfo (comma-separated)
		my ($fnln,$email,$roles) = split(/,/, $moreInfo);
		# Yes, even though I say FNLN it's really LN/FN
		my ($ln, $fn) = split('/', $fnln);
		$url = 'https://qualysapi.qualys.com/msp/user.php?action=add';
		$url .= '&send_email=1';
		$url .= "&first_name=$fn";
		$url .= "&last_name=$ln";
		$url .= "&role=$roles";
		$url .= "&email=$email";
		$url .= "&external_id=$qgID";		
	} else {
		# Shouldn't be here
		print "ERROR: Unknown action $action\n";
		return;
	}

	# If in audit only mode then we're done.
	if ($auditOnly) {
		print "AUDIT: $url\n";
		return;
	}
	
	return unless ($action eq 'EXTID');
	
	# Call the API and get a user list
	# TODO - unhardcode US SOC
    my $credentialsUrl = 'qualysapi.qualys.com:443';
    $ua->credentials(
        $credentialsUrl,
        'MSP Front Office',
        $qguser => $qgpassword
    );
    
    my $res = $ua->get($url);
    if (! $res->is_success) {
        my $error   = $res->status_line;
        print "ERROR:  Could not perform requested action:  $action $qgID $moreInfo\nERROR:  Received $error\n"
    } else {
    	print "SUCCESS: $action $qgID $moreInfo\n" if ($debug);
    }

}

# Indicate which command line arguments are supported and/or required
sub usage {
  my $msg = shift;
  $msg = "$appname $version" unless $msg;
  print <<EOF;

$msg 

$appname [arguments]

  Required Arguments:

    --aduser=SOMEUSER              AD username
    --adpassword=SOMEPASS          Password for aduser
    --base=dc=corp,dc=acme,dc.com  AD base patch
    --dc=SOMEDC                    Hostname or IP of domain controller
    --qguser=SOMEUSER              QualysGuard username
    --qgpassword=SOMEPASS          Password for qguser
    --groups=SOMEGROUP1=ROLE1,     Map of AD group membership to QG user role
       SOMEGROUP2=ROLE2,...
    --qgonlyusers=USERID1,USERID2  Listing of users that are in QG but won't have a matching
                                   account in AD.  Supports:
                                     If 'ANY' then users in QG with no corresponding
                                       AD account will be untouched.
                                     If 'NONE' then all QG users must have a corresponding
                                       AD account; any that do not will be disabled.
                                     IF 'USER1,USER2,...' then the specified users will be
                                       untouched and any other users without AD accounts
                                       will be deactivated.
    --auditonly                    Don't actually make any changes to QG, just show what
                                     would have been done.
    
    --help                         Provide usage information (what you are reading)

$appname is a simple proof-of-concept script to synchronize AD users with QualysGuard.  

It's designed to be run via CRON to make sure that a QualysGuard user gets deactivated when that user
is deprovisioned in Active Directory. It can also create users and flag cases (but not change them)
where a user's QualysGuard role should be changed.

Here's what it WILL do:

* Read a list of all users in Active Directory and determine the QG role they should have
  based on their AD group memberhsip.
* Try to match those up with users in QualysGuard (via external ID, first name + lastname, or email)
* Create accounts for users in AD that aren't in QualysGuard
* Deactivate accounts in QG for users that are disabled or non-existent in AD (with --qgonlyusers
  as the exceptions)
* Create a listing of actions that require UI work (such as when a manager becomes a reader)

Here's what it WON'T do:
* Synchronize passwords
* Provide single-sign-on
* Perform complex matching/permissions logic
* Be robust or support any kind of error conditions (again, it's a proof-of-concept)

Your command line should look something like this:

./$appname adQuery.pl --qguser=qguser_id --qgpassword=spork --dc=dc01.corp.acme.com --aduser=svcuser\@corp.acme.com
--adpassword=moby --base=OU=CorpUsers,DC=corp,DC=acme,DC=com --groups=PM=manager,TAM=reader --qgonlyusers=ANY --auditonly

EOF

    exit(1);
}
