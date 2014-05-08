    #!/usr/bin/perl
    use Text::CSV;
    use LWP::UserAgent;
    use Config::Simple;
    use HTTP::Request;
    use URI::Escape;
    require XML::Twig;

    my $file = 'info.csv';

    my $csv = Text::CSV->new();

    open (CSV, "<", $file) or die $!;

    my $firstname="";
    my $lastname="";
    my $title="";
    my $phone="";
    my $fax="";
    my $email="";
    my $add1="";
    my $add2="";
    my $city="";
    my $country="";
    my $state="";
    my $zip="";
    my $user_role="";
    my $business_unit="";
    my $asset_group="";
    my $ui_interface="";
    my $request;	        # HTTP request handle
    my $result;		# HTTP response handle
    my $server;		# QualysGuard server's FQDN hostname
    my $url;		# API access URL
    my $xml;		# Twig object handle
    my $username1="";
    my $password1="";
    my $target_user_file="";
    my $query="";
    my @words;
   
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
   		$message = $element->trimmed_text('MESSAGE');
   		   
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
   
   }
   
   my $conffile = ($ARGV[0] || 'usercreate.conf');
   my $conf = new Config::Simple($conffile);
   
   my $missing_elements;
   $missing_elements  = "username "  if (! $conf->param('username'));
   $missing_elements .= "password "  if (! $conf->param('password'));
   $missing_elements .= "targetuserfile " if (! $conf->param('targetuserfile'));
   
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
   
   if ($conf->param('targetuserfile')) {
   	 $target_user_file = $conf->param('targetuserfile');
   }
   
print "username=$username1\npassword=$password1\ntarget_file=$target_user_file\n";
   
   while (<CSV>) {
            next if ($. == 1);
            if ($csv->parse($_)) {
                my @columns = $csv->fields();
                $firstname=$columns[0];
                $firstname=uri_escape($firstname);
                $lastname=$columns[1];
                $lastname=uri_escape($lastname);
                $title=$columns[2];
                $title=uri_escape($title);
                $phone=$columns[3];
                $phone=uri_escape($phone);
                $fax=$columns[4];
                $fax=uri_escape($fax);
                $email=$columns[5];
                $add1=$columns[6];
                $add1=uri_escape($add1);
                $add2=$columns[7];
                $city=$columns[8];
                $city=uri_escape($city);
                $country=$columns[9];
                $country=uri_escape($country);
                $state=$columns[10];
                $zip=$columns[11];
                $user_role=$columns[12];
                $user_role=uri_escape($user_role);
                $business_unit=$columns[13];
                $business_unit=uri_escape($business_unit);
                $asset_group=$columns[14];
                $ui_interface=$columns[15];
            } else {
                my $err = $csv->error_input;
                print "Failed to parse line: $err";
            }
            
           	$query .="&first_name=$firstname&last_name=$lastname&title=$title&phone=$phone&email=$email&address1=$add1&city=$city&country=$country&user_role=$user_role&business_unit=$business_unit";
            	
            	if ($add2 ne ""){
            	$add2=uri_escape($add2);            	
	    	$query .= "&address2=$add2";
	    			
	    	}if ($asset_group ne ""){
	    	$asset_group=uri_escape($asset_group); 	
    		$query .= "&asset_groups=$asset_group";
	    		
	    	}if ($ui_interface ne ""){
	    	$ui_interface=uri_escape($ui_interface);	
    		$query .= "&ui_interface_style=$ui_interface";
	    		
	    	}if ($fax ne ""){
	    	$fax=uri_escape($fax);
    		$query .= "&fax=$fax1";
	    		
	    	}if ($zip ne ""){
		$zip=uri_escape($zip);
    		$query .= "&zip_code=$zip";
	    		
	    	}if ($state ne ""){
	    	$state=uri_escape($state);
   		$query .= "&state=$state";
	    	}
	
	    	my $show_url = 0;
	     
	     # XML::Twig is a handy way to process an XML document. We use it to attach
	     # various handlers, which are triggered whenever related tags are found
	     # in the XML document. We also attach an error() handler, which is
	     # triggered whenever Twig finds any errors.  The generic_return() 
	     #handler covers the case where a
	     # <GENERIC_RETURN> element is encountered.
	     
	     $url = "https://$server/msp/user.php?action=add$query";
	     #print "$url\n";

	    			$xml = new XML::Twig(
	    			TwigHandlers => {
	    				ERROR             => \&error,
	    				USER_OUTPUT    => \&generic_return,
	    			},
	    	);
	    	
	    
	    # Create an instance of the authentication user agent
	    
	        $ua  = LWP::UserAgent->new();
	        
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
}
        close CSV;
