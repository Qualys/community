#!/usr/bin/perl

use XML::Simple;
use XML::Twig;
use Data::Dumper;
use Storable;

use strict;
use warnings;

our $DEBUG = 1;

##################################################################

sub parse_qg_data {
    ### Parse data received from QG into a Perl data structure

    my $qg_service_name = $_[0];
    &write_log(7, "Parsing data for qg_service_name=[$qg_service_name]");

    my %twig_setup = (
		      'ticket_list.php' => [
					    ##TwigRoots => {
					    twig_roots => {
						'/REMEDIATION_TICKETS/TICKET_LIST/TICKET' => 1,
						'/REMEDIATION_TICKETS/TRUNCATION' => 1
					    },

					    #TwigHandlers => {
					    twig_handlers => {
						'/REMEDIATION_TICKETS/TICKET_LIST/TICKET' => \&ticket_handler,
						'/REMEDIATION_TICKETS/TRUNCATION' => \&truncation_handler
					    }
					    ],

		      'asset_range_info.php' => [
						 #TwigRoots => {
					    	 twig_roots => {
						     '/ASSET_RANGE_INFO/HOST_LIST/HOST/OPERATING_SYSTEM' => 1,
						     '/ASSET_RANGE_INFO/HOST_LIST/HOST/VULN_INFO_LIST/VULN_INFO' => 1,
						     },

						 #TwigHandlers => {
					    	  twig_handlers => {
						     '/ASSET_RANGE_INFO/HOST_LIST/HOST/OPERATING_SYSTEM' => \&os_handler,
						     '/ASSET_RANGE_INFO/HOST_LIST/HOST/VULN_INFO_LIST/VULN_INFO' => \&vuln_handler,
						     }
						 ]
		      );

    my $twig_params = $twig_setup{$qg_service_name};
    my $twig = new XML::Twig( @{$twig_params} );

    $twig->parse( $_[1] );
    ### $twig->print; ### DEBUG

}

##################################################################

sub truncation_handler {
    my ( $twig, $elt ) = @_;
    $main::since_ticket_number = $elt->{'att'}->{'last'};

    $twig->purge(); ### DEBUG
}

##################################################################

sub ticket_handler {
    ### Extracts various fields from /REMEDIATION_TICKETS/TICKET_LIST/TICKET

    my ( $twig, $elt ) = @_;
    my %resultset;

    ### Extract text ( or CDATA ) from the children named below.
    my @children = qw(
		      NUMBER
		      VULNINFO/SEVERITY
		      CREATION_DATETIME
		      CURRENT_STATE
		      ASSIGNEE/NAME
		      ASSIGNEE/EMAIL
		      ASSIGNEE/LOGIN
		      DETECTION/DNSNAME
		      DETECTION/NBHNAME
		      DETECTION/PORT
		      DETECTION/SERVICE
		      DETECTION/PROTOCOL
		      DETECTION/FQDN
		      DETECTION/SSL
		      VULNINFO/TITLE
		      VULNINFO/TYPE
		      VULNINFO/QID
		      VULNINFO/STANDARD_SEVERITY
		      DETAILS/DIAGNOSIS
		      DETAILS/CONSEQUENCE
		      DETAILS/SOLUTION
		      DETAILS/RESULT
		      DETECTION/IP
);

    foreach my $gi ( @children ) {
	my ( $child ) = $elt->get_xpath($gi);
	my $text;
	if ( defined $child ) {
	    $text = $child->text();
	    $text = $child->cdata() unless $text;
	}
	$resultset{$gi} = $text;
    }

    $resultset{'REOPEN'} = 0; ### default

    ### Extract HISTORY_LIST/HISTORY/RULE
    my ( %rules, @rules_list );
    my ( $history_list ) = $elt->get_xpath('HISTORY_LIST');
    if ( defined $history_list ) {

	### &write_log(7, "history_list is defined.");

	### Extract HISTORY/RULE
	my ( @history_rules ) = $history_list->get_xpath('HISTORY/RULE');
	foreach my $history_rule ( @history_rules ) {
	    my $text = $history_rule->text();
	    $text = $history_rule->cdata() unless $text;

	    unless ( exists $rules{$text} ) {
		push @rules_list, $text;
	    }

	    $rules{$text}++;
	}

	### Determine whether this ticket is a re-open.
	### Extract HISTORY/STATE
	my $first_state = $history_list->get_xpath('HISTORY/STATE', 0);
	if ( defined $first_state ) {
	    my $old_state = $first_state->first_child('OLD');
	    my $new_state = $first_state->first_child('NEW');
	    if ( (defined $old_state) && (defined $new_state) ) {
		my $old_text = $old_state->text();
		my $new_text = $new_state->text();
		if ( ($old_text eq 'CLOSED') && ($new_text eq 'OPEN') ) {
		    $resultset{'REOPEN'} = 1;
		}
	    }
	}

	### Extract latest date in this ticket's history.
	### HISTORY_LIST is reverse chronological.
	my $first_datetime = $history_list->get_xpath('HISTORY/DATETIME', 0);
	if ( defined $first_datetime ) {
	    my $first_datetime_text = $first_datetime->text();

	    ### &write_log(7, "Found first_datetime=[$first_datetime_text]");
	    $resultset{'LATEST_DATETIME'} = $first_datetime->text();
	}

    }

    ### LATEST_DATETIME is the latest of the two dates.
    if ( &tne_datediff( $resultset{'LATEST_DATETIME'}, $resultset{'CREATION_DATETIME'}  ) < 0 ) {
	$resultset{'LATEST_DATETIME'} = $resultset{'CREATION_DATETIME'};
    }


    ### This is an aggregation of several rules extracted from HISTORY_LIST
    $resultset{'RULE'} = join ',', @rules_list;


    if ( 0 ) {
	### DEBUG: For debugging!
	foreach my $key ( keys %resultset ) {
	    my $message = "$key=[" . $resultset{$key} . "]";
	    &write_log( 7, $message );
	}
    }

    $twig->purge(); ### DEBUG

    &write_ticket(\%resultset);
}
##################################################################

sub os_handler {
    ### Extracts OPERATING_SYSTEM from /ASSET_RANGE_INFO/HOST_LIST/HOST/OPERATING_SYSTEM

    my ( $twig, $elt ) = @_;


    my $os = $elt->text() || $elt->cdata();
    $os =~ s/^\s+|\s+$//g;

    ### &write_log(7, "OS=[$os]" );
    $main::operating_system = $os if $os;

    $twig->purge(); ### DEBUG

}

##################################################################

sub vuln_handler {
    ### Extracts last_logged_on_user from  /ASSET_RANGE_INFO/HOST_LIST/VULN_INFO_LIST/VULN_INFO

    my ( $twig, $elt ) = @_;
    my %resultset;

    ### Extract text ( or CDATA ) from the children named below.
    my @children = qw(
			QID
			TYPE
			PORT
			SERVICE
			FQDN
			PROTOCOL
			SSL
			RESULT
			FIRST_FOUND
			LAST_FOUND
			TIMES_FOUND
			VULN_STATUS
			TICKET_NUMBER
			TICKET_STATE
			);

    foreach my $gi ( @children ) {
	my ( $child ) = $elt->get_xpath($gi);
	if ( defined $child ) {
	    my $text = $child->text() || $child->cdata();
	    $text =~ s/^\s+|\s+$//g;
	    $resultset{$gi} = $text;
	}
    }

    if ( ($resultset{'QID'} eq "$main::qid" ) && ($resultset{'TICKET_NUMBER'} eq "$main::ticket_number") ) {
    $main::asset_range_info{vuln_info_qid} = $resultset{'QID'};
    $main::asset_range_info{vuln_info_type} = $resultset{'TYPE'};
    $main::asset_range_info{vuln_info_port} = $resultset{'PORT'};
    $main::asset_range_info{vuln_info_service} = $resultset{'SERVICE'};
    $main::asset_range_info{vuln_info_fqdn} = $resultset{'FQDN'};
    $main::asset_range_info{vuln_info_protocol} = $resultset{'PROTOCOL'};
    $main::asset_range_info{vuln_info_ssl} = $resultset{'SSL'};
    $main::asset_range_info{vuln_info_result} = $resultset{'RESULT'};
    $main::asset_range_info{vuln_info_fir_found} = $resultset{'FIRST_FOUND'};
    $main::asset_range_info{vuln_info_las_found} = $resultset{'LAST_FOUND'};
    $main::asset_range_info{vuln_info_times_found} = $resultset{'TIMES_FOUND'};
    $main::asset_range_info{vuln_info_status} = $resultset{'VULN_STATUS'};
    $main::asset_range_info{vuln_info_tic_num} = $resultset{'TICKET_NUMBER'};
    $main::asset_range_info{vuln_info_tic_state} = $resultset{'TICKET_STATE'};
    }
     
###    foreach my $key ( sort keys %resultset ) {
###	&write_log(7, "$key=[" . $resultset{$key} . "]" ); ### DEBUG
###    }

    if ( $resultset{'QID'} == 105311 ) {

	### 
	if ( $resultset{'RESULT'} =~ /^.+?\sDefaultUserName\s*=\s*(\S+)\s+/s ) {
	    $main::last_logged_on_user = $1;
	} else {
	    &write_log(4, "ERROR: While parsing LAST_LOGGED_ON_USER");
	    $main::last_logged_on_user = $resultset{'RESULT'};
	}

	&write_log(7, "LAST_LOGGED_ON_USER=[" . $main::last_logged_on_user . "]" );
    }

    $twig->purge(); ### DEBUG
}

##################################################################

sub glossary_handler {
    my $xml_file = shift;

    my $simple = XML::Simple -> new();
    my $tree = $simple->XMLin($xml_file);

    my $qid = $main::qid;
    $qid = "qid_".$qid;
    
    $main::asset_range_info{glos_sol} = $tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{SOLUTION};
    $main::asset_range_info{glos_cat} = $tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{CATEGORY};
    $main::asset_range_info{glos_qid_con} = $tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{QID}->{content};
    $main::asset_range_info{glos_qid_id} = $tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{QID}->{id};
    $main::asset_range_info{glos_title} = $tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{TITLE};
    $main::asset_range_info{glos_sev} = $tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{SEVERITY};
    $main::asset_range_info{glos_cust} = $tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{CUSTOMIZED};
    $main::asset_range_info{glos_threat} = $tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{THREAT};
    $main::asset_range_info{glos_impact} = $tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{IMPACT};
    $main::asset_range_info{glos_comp} = $tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{COMPLIANCE};
    $main::asset_range_info{glos_update} = $tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{LAST_UPDATE};
    $main::asset_range_info{glos_cvss_tem} = &get_string($tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{CVSS_SCORE}->{CVSS_TEMPORAL});
    $main::asset_range_info{glos_cvss_base} = &get_string($tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{CVSS_SCORE}->{CVSS_BASE});
	# set cvss_base_score_source
	if ($main::asset_range_info{glos_cvss_base} =~ m/service/i){
        $main::asset_range_info{cvss_base_score_source} = 'service';
	}else {
		if ($main::asset_range_info{glos_cvss_base} =~ m/N\/A/i){
			$main::asset_range_info{cvss_base_score_source} = 'N/A';
		}else{
        	$main::asset_range_info{cvss_base_score_source} = 'nist';
		}
	}
    $main::asset_range_info{glos_vend_id_url} = &get_string($tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{VENDOR_REFERENCE_LIST}->{VENDOR_REFERENCE});
    $main::asset_range_info{glos_cve_id_url} = &get_string($tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{CVE_ID_LIST}->{CVE_ID});
    $main::asset_range_info{glos_bugtraq_id_url} = &get_string($tree->{GLOSSARY}->{VULN_DETAILS_LIST}->{VULN_DETAILS}->{$qid}->{BUGTRAQ_ID_LIST}->{BUGTRAQ_ID});

    $main::asset_range_info{host_ip} = $tree->{HOST_LIST}->{HOST}->{IP};
    $main::asset_range_info{host_trac_meth} = $tree->{HOST_LIST}->{HOST}->{TRACKING_METHOD};
    $main::asset_range_info{host_dns} = $tree->{HOST_LIST}->{HOST}->{DNS};
    $main::asset_range_info{host_netbios} = $tree->{HOST_LIST}->{HOST}->{NETBIOS};
    $main::asset_range_info{host_op_sys} = $tree->{HOST_LIST}->{HOST}->{OPERATING_SYSTEM};
    # group title is array ref. so deref it or a string
    if (defined ($tree->{HOST_LIST}->{HOST}->{ASSET_GROUPS}->{ASSET_GROUP_TITLE})){
    my $arref = $tree->{HOST_LIST}->{HOST}->{ASSET_GROUPS}->{ASSET_GROUP_TITLE};
    my $string;
    if ($arref =~ m/ARRAY/){
    my @array = @{$arref};
    $string = join (',', @array);
    } elsif (!(ref $arref)){
    $string = $arref;
    }
    $main::asset_range_info{host_asset_gr_title} = $string;
    } # if

}

######################################################################
# NEW Code for processing Glossary using Twig module
##

sub glossary_twig_handler {
    my $xml_file = shift;

 my $twig = new XML::Twig(
				twig_roots => {
 					'/ASSET_RANGE_INFO/GLOSSARY/VULN_DETAILS_LIST' => 1,
 					'/ASSET_RANGE_INFO/HOST_LIST' => 1
 					},
 				twig_handlers => {
 					'/ASSET_RANGE_INFO/GLOSSARY/VULN_DETAILS_LIST' => \&proc_vuln_handler,
 					'/ASSET_RANGE_INFO/HOST_LIST' => \&proc_hosts_handler
 					},
 				pretty_print => 'indented'
			);
##    my $twig = XML::Twig -> new(
##                  # the twig will include just the Glossary and the HOST_LIST
##                  twig_roots => { 'GLOSSARY/VULN_DETAILS_LIST' => \&proc_vuln_handler,
##                                  'HOST_LIST' => \&proc_hosts_handler
##                  },
##                  pretty_print => 'indented'
##               );
    ### print(" File name is: %s \n", $xml_file);  ### DEBUG
    $twig->parse( $xml_file ); 

}

# Handler used for processing Glossary VULN Details
sub proc_vuln_handler {
    
    my ($twig, $GLOSSARY_VULN_DETAILS) = @_;

    my @vuln_details; 
    # First check whether we can proceed or not
    if ( (defined $GLOSSARY_VULN_DETAILS) and $GLOSSARY_VULN_DETAILS->has_child('VULN_DETAILS') ) {
        @vuln_details  = $GLOSSARY_VULN_DETAILS->findnodes('VULN_DETAILS');
    } 
    else { 
        &write_log(7, " RETURNING -- not present VULN details ");  ### DEBUG
        printf " RETURNING -- not present VULN details \n";  ### DEBUG
        return 1;
    }
    my $qid = $main::qid; 
    #$qid = 19084;   # Test QID
    my $qid_str = "qid_".$qid;

    my $val = 'VULN_DETAILS';
    my $exp = qq{VULN_DETAILS[ \@id="$qid_str"]};
    #my $exp = qq{//VULN_DETAILS_LIST/VULN_DETAILS};
    #printf " EXPRESSION ". $exp;  ### DEBUG
    my $VULN = undef ;
    
    #$GLOSSARY_VULN_DETAILS->get_xpath( $exp )->print; # This oddly does not work and hence a loop is used.

    foreach my $vuln ( @vuln_details ) {
        my $chk_qid =  $vuln->field('QID'); 
        if ($chk_qid == $qid) {
           $VULN = $vuln;  # found the data we were looking for
           last;
        }
    }
   
    if ( (defined $VULN) ) {
       #$VULN->print;  ### DEBUG
    }
    else {
       return 2;
    }
    
    $main::asset_range_info{glos_sol} = $VULN->field('SOLUTION');
    $main::asset_range_info{glos_cat} = $VULN->field('CATEGORY');
    $main::asset_range_info{glos_qid_con} = $VULN->field('QID');
    #$main::asset_range_info{glos_qid_id} = $VULN->first_child('QID')->{'att'}->{'id'};
    $main::asset_range_info{glos_qid_id} = $qid_str;
    $main::asset_range_info{glos_title} = $VULN->field('TITLE');
    $main::asset_range_info{glos_sev} = $VULN->field('SEVERITY');
    $main::asset_range_info{glos_cust} = $VULN->field('CUSTOMIZED');
    $main::asset_range_info{glos_threat} = $VULN->field('THREAT');
    $main::asset_range_info{glos_impact} = $VULN->field('IMPACT');
    $main::asset_range_info{glos_comp} = $VULN->field('COMPLIANCE');
    $main::asset_range_info{glos_update} = $VULN->field('LAST_UPDATE');
    if ($VULN->has_child('CVSS_SCORE') and 
        $VULN->first_child('CVSS_SCORE')->has_child('CVSS_TEMPORAL') ) {  
        $main::asset_range_info{glos_cvss_tem} = 
               $VULN->first_child('CVSS_SCORE')->findvalue('CVSS_TEMPORAL');
    }
    if ($VULN->has_child('CVSS_SCORE') and $VULN->first_child('CVSS_SCORE')->has_child('CVSS_BASE') ) {  
        $main::asset_range_info{glos_cvss_base} = 
               $VULN->first_child('CVSS_SCORE')->findvalue('CVSS_BASE');
	# set cvss_base_score_source
	if ($main::asset_range_info{glos_cvss_base} =~ m/service/i){
        $main::asset_range_info{cvss_base_score_source} = 'service';
	}else {
		if ($main::asset_range_info{glos_cvss_base} =~ m/N\/A/i){
			$main::asset_range_info{cvss_base_score_source} = 'N/A';
		}else{
        	$main::asset_range_info{cvss_base_score_source} = 'nist';
		}
	}
    }
    if ($VULN->has_child('VENDOR_REFERENCE_LIST') and 
        $VULN->first_child('VENDOR_REFERENCE_LIST')->has_child('VENDOR_REFERENCE') ) {  
        $main::asset_range_info{glos_vend_id_url} = 
               $VULN->first_child('VENDOR_REFERENCE_LIST')->findvalue('VENDOR_REFERENCE');
    }
    if ($VULN->has_child('CVE_ID_LIST') and $VULN->first_child('CVE_ID_LIST')->has_child('CVE_ID') ) {
        my @url_array =  $VULN->first_child('CVE_ID_LIST')->findnodes('CVE_ID/URL') ;
        my $string;
        foreach my $elem (@url_array){
           $string .= $elem->findvalue('.') ." \n";
        }
        $main::asset_range_info{glos_cve_id_url} = $string;
    }
    if ($VULN->has_child('BUGTRAQ_ID_LIST') and $VULN->first_child('BUGTRAQ_ID_LIST')->has_child('BUGTRAQ_ID') ) {
        my @url_array = $VULN->first_child('BUGTRAQ_ID_LIST')->findnodes('BUGTRAQ_ID/URL')  ;
        my $string;
        foreach my $elem (@url_array){
           $string .= $elem->findvalue('.') ." \n";
        }
        $main::asset_range_info{glos_bugtraq_id_url} = $string;
    }

    ###  DEBUG Info Begin
    #printf "\nIn proc_vuln_handler\n" ;
    #printf " QID %s \n",  $main::asset_range_info{glos_qid_id};
    #if ( defined  $main::asset_range_info{glos_cve_id_url} ) {
       #printf " URLS ".  $main::asset_range_info{glos_cve_id_url}. "\n";
    #}
    ###  DEBUG Info End

    $twig->purge;

}

# Handler used for processing HOST_LIST 

sub proc_hosts_handler {
    
    my ($twig, $HOST_LIST) = @_;

    my @host_list = undef;
    if ( (defined $HOST_LIST) and $HOST_LIST->has_child('HOST') ) {
        @host_list  = $HOST_LIST->findnodes('HOST');
    } 
    else { 
        &write_log(7, " RETURNING -- not present HOST details ");  ### DEBUG
        printf " RETURNING -- not present HOST details \n";  ### DEBUG
        return 1;
    }

    my $ticket_no = $main::ticket_number; 
    my $HOST = undef ;
    my $chk_ticket =  0; 
    #&write_log(7, " TICKET_NUMBER  $ticket_no ");  ### DEBUG
    #printf " Main Ticket %s \n", $ticket_no;  ### DEBUG
    foreach my $host ( @host_list ) {
        my @tickets_array =  $host->findnodes('VULN_INFO_LIST/VULN_INFO/TICKET_NUMBER') ;
        foreach my $ticket ( @tickets_array ) {
           if ($ticket->findvalue('.') == $ticket_no) {
              #printf " Check Ticket %s \n", $ticket->findvalue('.');  ### DEBUG
              $HOST = $host;  # found the data we were looking for
              last;
           }
           last if (defined $HOST) ;   ## exit outer loop
        }
    }

    if ( !(defined $HOST) ) {
      $HOST = $HOST_LIST->first_child('HOST');
    }

    $main::asset_range_info{host_ip} = $HOST->field('IP');
    $main::asset_range_info{host_trac_meth} = $HOST->field('TRACKING_METHOD');
    $main::asset_range_info{host_dns} = $HOST->field('DNS');
    my $dns_txt = "Host DNS ". $main::asset_range_info{host_dns};
    #&write_log(7, " DNS  $dns_txt ");  ### DEBUn::asset_range_info{host_dns}G
    #printf " %s \n", $dns_txt;  ### DEBUG
    $main::asset_range_info{host_netbios} = $HOST->field('NETBIOS');
    $main::asset_range_info{host_op_sys} = $HOST->field('OPERATING_SYSTEM');
    # group title is array ref. so deref it or a string
    if (defined ($HOST->first_child('ASSET_GROUPS')->first_child('ASSET_GROUP_TITLE'))){
       my @arref = $HOST->first_child('ASSET_GROUPS')->findnodes('ASSET_GROUP_TITLE');
       my $string = "";
       my @array = @arref;
       foreach my $hashref (@array){
          $string .= $hashref->findvalue('.') ." ";
       }
       $main::asset_range_info{host_asset_gr_title} = $string;
    }

    ###  DEBUG Info Begin
    #printf "\nIn proc Hosts_handler %s ",  $main::asset_range_info{host_ip};
    #printf "\n Array Ref ".  $main::asset_range_info{host_asset_gr_title}."\n";
    ###  DEBUG Info End

    $twig->purge;
}

# Handler used for processing HOST_LIST (used for testing) 

sub proc_test_hosts_handler {
    
    my ($twig, $HOST_LIST) = @_;

    printf "\nIn proc Hosts IP " . $HOST_LIST->first_child('HOST')->first_child_text("IP");
    my $dns = $HOST_LIST->first_child('HOST')->field('DNS');
    printf " DNS $dns \n"  ;
    return 1;
}

######################################################################
sub get_string {
	my $value = shift;
	my $string;

    # this will be either a hashref or arrayref of hashrefs.
    if (defined ($value)){
    my $ref_type = $value;
	return $ref_type if !(ref $ref_type); # if the value is not either array or hash ref
    my @array = @{$ref_type} if $ref_type =~ m/ARRAY/i;
    my %hash = %{$ref_type} if $ref_type =~ m/HASH/i;
    if (@array){
    foreach my $hashref (@array){
       my %hash = %{$hashref};
       while (my($k,$v) = each(%hash)){
       $string .= $k.' = '.$v."\n";
       } # while
    } # foreach
    } # if @array

    if (%hash){
       while (my($k,$v) = each(%hash)){
       $string .= $k.' = '.$v."\n";
       } # while
    } # if defined %hash
	} else {
		$string = 'N/A';
	}
	return $string;
}
########################################################################
sub write_ticket {
    ### Writes a ticket to a local cache.
    ### Ticket filenames are based on the unique QG ticket number.
    ### Additional key/value pairs might be retrieved from QualysGuard
    ### and appended to this file.

    my ( $hashref ) = @_;

    my $severity_level = $hashref->{'VULNINFO/SEVERITY'} || 'NULL';
    my $ticket_number = sprintf "%04d", $hashref->{'NUMBER'};

    my @tickets = &main::get_tickets_from_cache($severity_level);
    foreach my $cached_ticket_file ( @tickets ) {
	my ( $cached_timestamp, $cached_ticket_number ) = split /_/, $cached_ticket_file;
	if ( $cached_ticket_number == $ticket_number ) {
	    if ( unlink $cached_ticket_file ) {
		&write_log(7, "Deleted ticket_file=[$cached_ticket_file]");
		$main::state->param('tickets_in_cache', $main::state->param('tickets_in_cache') - 1);
	    } else {
		&write_log(7, "Could not delete ticket_file=[$cached_ticket_file][$!]");
	    }
	}
    }

    my $ticket_file = $main::config{'TNE.cache_dir'} . "/$severity_level/" . time() . "_";
    $ticket_file .= $ticket_number;
    &write_log(7, "Writing ticket_file=[$ticket_file]");

    if ( Storable::store( $hashref, $ticket_file ) ) {
	### Increment tickets in cache.
	$main::state->param('tickets_in_cache', $main::state->param('tickets_in_cache') + 1);
	$main::state->save();
	&write_log(7, qq{Wrote ticket to ticket_file=[$ticket_file]});
    } else {
	&write_log(0, qq{ERROR: Could not create ticket file [$ticket_file][$!]});
    }

}

##################################################################


1;
