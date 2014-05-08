#!/usr/bin/perl

##################################################################
###
### TNE ( Ticket Notification Engine )
### $Revision: 1.12 $
###
### This script implements a one-way flow of tickets from
### QualysGuard to a customers ticketing application
###
###
##################################################################

our $VERSION = (split( /\s+/, q$Revision: 1.12 $ ))[1];

BEGIN {
    ### Change the present working directory.
    my $filepath = $0;
    if ( $filepath =~ m@/@ ) {
        $filepath =~ s@/[^/]+$@/@;
	push @INC, $filepath;
	chdir ($filepath) or die "ERROR: Could not cd to [$filepath][$!]\n";
    }
}

use lib qw(. ../bin);

require "parser.pl";
use Data::Dumper;
use Date::Parse;
use Text::Template;
use URI::Escape;
use LWP::UserAgent;
use Net::SMTP;
use Config::Simple;
use LockFile::Simple qw(lock unlock);
use Getopt::Long;
use File::Path;
use strict;

our $DEBUG = 1;
my @severity_levels = qw( 5 4 3 2 1 );
my $scriptname = "tne.pl";
our (
     %config,
     $state,
     $since_ticket_number,
     $operating_system,
     $last_logged_on_user,
     $qid,
     $ticket_number,
     %asset_range_info,
     );
my $success_count = 0;
my $failure_count = 0;
my $failure_msg = "";
my $test_dir = 'test';
my ($test_mode, $help, $write_output, $retrieve_only, $send_cached);
my (%rule_map,$lockmgr,$got_lock,$state_file);
unless ( &initialize() ) {
    my $msg = "ERROR: Initialization failed! Exiting.";
    print "$msg\n";
    &write_log(0, "$msg");
    exit(0);
}

&write_log(7, "Begin=======================");
&main();
&write_log(7, "End=========================");

##################################################################

sub main {
    ### This subroutine contains the main logic for the TNE application.

    if ( $help ) {
	&show_usage();
	&write_log(7, "Showing usage.");
	return;
    }

    ### Retrieve new tickets, cache them, and transmit them to the ticketing system.
    foreach my $severity_level ( @severity_levels ) {

	if ( $send_cached ) {
	    &write_log(7, "Send-cached: NOT retrieving new tickets.");
	} else {

	    ### Check if cache is full.
	    if ( $state->param('tickets_in_cache') >= $config{'TNE.max_tickets_to_cache'} ) {
		### Cache is full!

		my $message = qq{ERROR: The cache is configured for a maximum of };
		$message .= $config{'TNE.max_tickets_to_cache'} . " tickets, and it has ";
		$message .= $state->param('tickets_in_cache') . " tickets."; 
		&write_log(6, $message);

		if ( $retrieve_only ) {
		    &write_log(5, "Retrieve-only: NOT sending tickets.");
		} else {
		    &write_log(6, "Trying to send some tickets to make room.");

		    ### Send tickets to make some room.
		    my $result = &send_im_data($severity_level);
		    if ( $result == 1 ) {
			&write_log(7, "Sent data for severity level [$severity_level]");
		    } elsif ( $result == 0 ) {
			&write_log(4, "Reached max_tickets_per_run limit.");
			last;
		    } else {
			&write_log(4, "Encountered an error reading cache.");
			last;
		    }

		    if ( $state->param('tickets_in_cache') >= $config{'TNE.max_tickets_to_cache'} ) {
			my $message = qq{Not enough tickets for severity level [$severity_level] were sent to customer };
			$message .= qq{to make some room in the cache. };
			$message .= qq{Continuing with next severity level.};
			&write_log(6, $message);
			next;
		    } else {
			my $message = qq{Enough tickets for this severity level were sent to customer, };
			$message .= qq{to make room in the cache.};
			&write_log(6, $message);
		    }
		}
	    }

	    ### If the retrieval of a large dataset in many parts was interrupted,
	    ### pick up where we left off.
	    my $since_ticket_number_name = 'since_ticket_number_' . $severity_level;
	    if ( 
		 (!$since_ticket_number) &&
		 $state->param($since_ticket_number_name) &&
		 (! ref $state->param($since_ticket_number_name) )
		 ) {
		$since_ticket_number = $state->param($since_ticket_number_name);
		&write_log(6, "Read $since_ticket_number_name from state as [$since_ticket_number]");
	    }

	    my $timestamp_keyname = "time_severity_" . $severity_level;
	    my ( $qg_service_name, $qg_params_hashref, $qg_xml );

	    ### Get tickets from tickets_list.php
	    $qg_service_name = 'ticket_list.php';

	    $qg_params_hashref = {
		'modified_since_datetime' => $state->param($timestamp_keyname),
		'show_vuln_details' => 1
		};
	    unless ( $severity_level eq 'NULL' ) {
		$qg_params_hashref->{'vuln_severities'} = $severity_level;
	    }

	    ### Handle the truncation of a large dataset.
	    if ( defined $since_ticket_number ) {
		$qg_params_hashref->{'since_ticket_number'} = $since_ticket_number;
		$since_ticket_number = undef;
	    }

    	# get all the other attributes specified in the config file.
    	&get_attributes($qg_params_hashref, $severity_level);
	    $qg_xml = &get_qg_data( $qg_service_name, $qg_params_hashref );

	    unless ( length($qg_xml) > 10 ) {
		my $message = "ERROR: Did not receive a valid response from QualysGuard. [$qg_xml]";
		&write_log(2, $message);
		next;
	    }

	    ### Parse XML. This might set $since_ticket_number
	    ### This is the only place that sets $since_ticket_number
	    &parse_qg_data( $qg_service_name, $qg_xml );
	    
	    &write_log(7, "Parsed XML from $qg_service_name");
	    
	    ### Handle truncation of dataset.
	    if ( $since_ticket_number ) {
		&write_log(5, "Dataset was truncated. The next ticket number is [$since_ticket_number]");
		if ( defined $qg_params_hashref->{'since_ticket_number'} ) {
		    if ( $qg_params_hashref->{'since_ticket_number'} != $since_ticket_number ) {
			### a continued dataset is continued further. overwrite state.
			$state->param($since_ticket_number_name, $since_ticket_number);
			$state->save();
		    }
		} else {
		    ### a dataset was truncated. store this state.
		    $state->param($since_ticket_number_name, $since_ticket_number);
		    $state->save();
		}
	    } else {
		if ( defined $qg_params_hashref->{'since_ticket_number'} ) {
		    ### no further continue. delete from state.
		    &write_log(5, "Dataset was retrieved completely. Deleting $since_ticket_number_name from state.");
		    $state->param($since_ticket_number_name, undef);
		    $state->save();
		}
	    }	
	}

	if ( $retrieve_only ) {
	    &write_log(5, "Retrieve-only: NOT sending tickets.");
	} else {

	    &write_log(7, "Sending data...");
	
	    ### Send tickets to customer.
	    unless ( &send_im_data($severity_level) ) {
		&write_log(4, "Reached max_tickets_per_run limit. Exiting.");
		last;
	    }
	}

	if ( $since_ticket_number ) {
	    ### Repeat this loop with the same severity level,
	    ### because the dataset was truncated.
	    redo;
	}
    } ### END: for

	# at the end if statistical data is on in the config file, that means
	# customers wants to get number of counts of success and failures
	if ($config{'ADMIN_EMAILS.statistical_data'} =~ m/on/i){
        my $msg = "Tickets successfully processed: $success_count\n Number of failures with messages: $failure_count\n$failure_msg\n";
		&write_log(3, "$msg");
   	}
 
	# if this script runs with --test-mode, at the end clean up the 
	# cache directory and state.conf in the test dir.
	END {
	if ($test_mode){
        rmtree $config{'TNE.cache_dir'};
		unlink ("state.conf");
        rmtree $config{'TNE.log_dir'};
	}
	}
}

##################################################################

sub read_config {
    ### Read configuration parameters from a config file.

    my $config_file;
    my $choose_config_file;
       $choose_config_file = 'tne.conf';
    my @config_path = ( $_[0], "../conf/$choose_config_file" );

    foreach my $config_location ( @config_path ) {
	if ( -e $config_location ) {
	    $config_file = $config_location;
	    last;
	}
    }

    eval {
	Config::Simple->import_from($config_file, \%config);	
    };
    if ( $@ ) {
	die ("ERROR: While reading configuration from config_file $choose_config_file\n ");
    }

    return 1;
}

##################################################################

sub write_log {
    ### This subroutine implements the logging/alerts interface.
    ### It takes two parameters, a severity and a message.
    ### The severity ranges from 0 to 7, with 0 being the highest severity.
    ### ( Severity levels are like syslog severity levels ).

    my ( $severity, $message ) = @_;

    my ($package, $filename, $line) = caller;
    $filename =~ s/^\W+//;

    ### Write this message to a log file.
    my $log_file = $config{'TNE.log_dir'};
    $log_file .= '/' unless $log_file =~ /\/$/;
    $log_file .= $config{'TNE.log_file'};

    if ( open(LOG, ">>$log_file" ) ) {
	my $old_fh = select(LOG);
	$| = 1;
	select($old_fh);
	### $message =~ s/:/\\:/g;
    my $now=&get_syslog_time();

	print LOG "$now $severity:$filename:$line:$message";
	print LOG "\n" unless $message =~ /\n$/;
	close(LOG);
    } else {
	my $message = "ERROR: Could not create log file [$log_file][$!]\n";
	&send_alert( $message, "CANNOT WRITE LOG");
	print STDERR $message, "\n";
    }

    # if notification in config file is on, then send alert. If it is off
    # dont send
    my $notifications = $config{'ADMIN_EMAILS.notifications'};
    if ( ($severity < 4) && ($notifications =~ m/on/i)) {
	### Send an email alert
	&send_alert($message);
    }
    
}

##################################################################

sub write_output {
    ### Write a ticket command to a tickets file.

    my $output_file =  $config{'TNE.log_dir'} . '/tickets.sh';
    if ( open(TICKETS, ">>$output_file" ) ) {
	foreach my $message ( @_ ) {
	    print TICKETS $message;
	}
	close(TICKETS);
    }
}

##################################################################

sub send_alert {
    ### Send an email alert to administrators.

    my ( $email_message, $cannnot_write_log ) = @_;

    &write_log(7, 'ADMIN_EMAILS.host=[' . $config{'ADMIN_EMAILS.host'} . ']') unless $cannnot_write_log;

    my ( $smtp );
	$smtp = &check_for_smtp($config{'ADMIN_EMAILS.host'});
	if ((! defined $smtp)){
	my $message = "ERROR: while getting SMTP connection [$@] 'ADMIN_EMAILS.host'";
	if ( $cannnot_write_log ) {
	    die "ERROR: Cannot send email [$message] and cannot write to log [$email_message].";
	} else {
	    &write_log(5, $message);
		print "$message\n";
	}
	return;
    } else {
	    &write_log(7, "\$smtp is defined") unless $cannnot_write_log;
	eval {
	    my $from_email = $config{'ADMIN_EMAILS.from'};
	    $smtp->mail($from_email);

	    my @recipients = ref $config{'ADMIN_EMAILS.admins'} ? @{ $config{'ADMIN_EMAILS.admins'} } : split /\,/, $config{'ADMIN_EMAILS.admins'};

	    my $recipients_message = q{Sending email to the following: [};
	    $recipients_message .= (join '|', @recipients);
	    $recipients_message .= ']';
	    &write_log(7, $recipients_message) unless $cannnot_write_log;
        my $res_string = join(',',@recipients);
	    $smtp->to(@recipients);

	    $smtp->data();
	    $smtp->datasend("From: $from_email\n");

	    $smtp->datasend("To: $res_string\n");
	    $smtp->datasend("Subject: TNE Alert!\n");
	    $smtp->datasend("\n\n$email_message\n");

	    $smtp->datasend("\n\n====================================\n");
	    $smtp->datasend("This alert message is autogenerated by the TNE (Ticket Notification Engine) script.\n");
	    $smtp->dataend();
	    $smtp->quit;
	};
	
	if ( $@ ) {
	    my $message = "ERROR: while sending email [$@]";
	    if ( $cannnot_write_log ) {
		die "ERROR: Cannot write log [$email_message], and cannot send email [$@].";
	    } else {
		&write_log(4, $message);
	    }
	}
    }
}

##################################################################

sub get_qg_data {
    ### Send a request to QualysGuard and retrieve data.
    ### This subroutine takes two paramets.
    ### A QualysGuard service name, and a reference to a hash
    ### containing various query parameters to pass to the web service.

    my ( $qg_service_name, $params_hashref ) = @_;
    my $params_string;

    ### Create a URLencoded string with all params.
    if ( defined $params_hashref ) {
	$params_string = join '&', ( map { uri_escape($_) . '=' . uri_escape( $params_hashref->{$_} ) } (keys %{$params_hashref}) );
    }

    my $url = $config{'QG.url'};
    $url .= $qg_service_name;
    $url .= "?$params_string" if $params_string;


    ### Proxy configuration
    $ENV{'HTTPS_PROXY'} = $config{'QG.proxy'} if $config{'QG.proxy_url'};
    $ENV{'HTTPS_PROXY_USERNAME'} = $config{'QG.proxy_username'} if $config{'QG.proxy_username'};
    $ENV{'HTTPS_PROXY_PASSWORD'} = $config{'QG.proxy_password'} if $config{'QG.$proxy_password'};

    my $ua = LWP::UserAgent->new(
	    			# 'agent' => 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; .NET CLR 1.0.3705 tne.pl $Revision: 1.12 $)',
                                 'agent' => "libwww - ".$scriptname." ".$VERSION,
                                 'requests_redirectable' => [],
                                 'timeout' => $config{'QG.timeout'},
                                 );

    # $ua->ssl_opts(SSL_ca_file => Mozilla::CA::SSL_ca_file());
    # LWP should not handle HTTPS proxy
    $ua->proxy(https => undef); 
    my $err_msg;
    for ( my $attempt = 0; $attempt < $config{'QG.max_transmission_attempts'}; $attempt++ ) {
	my $req = HTTP::Request->new(GET => $url );

	### &write_log(6, "username=[" . $config{'QG.username'} . "]\n");
	### &write_log(6, "password=[" . $config{'QG.password'} . "]\n");

	$req->authorization_basic($config{'QG.username'}, $config{'QG.password'} );
	my $res = $ua->request($req);
	&write_log(6, "url=[$url]\n");
	
	if ($res->is_success) {
	    my $content = $res->content;
	    &write_log(7, "Successfully retrieved HTML response");
	    return $content;
	} else {
	    $err_msg = "ERROR: While retrieving data from QualysGuard: [" . $res->message . "]";
	    $err_msg .= " on attempts $config{'QG.max_transmission_attempts'}." if $attempt == ($config{'QG.max_transmission_attempts'} - 1);
	    &write_log(5, $err_msg);
		# do not continue if we do not get valid response from QG here.
		if ($attempt == ($config{'QG.max_transmission_attempts'} - 1)){
	    	&write_log(3, $err_msg);
			die ("$err_msg\n");
		}
	}
    }

}

##################################################################

sub send_im_data {
    ### Post some data to customer 
    ### and retrieve the response.
    ### This subroutine will use either POSTEMSG or SMTP protocol.

    ### Returns true if more tickets can be sent,
    ### false if the max_tickets_per_run limit is reached.

    my ( @severity_levels ) = @_;

    my $can_send_more_tickets = 1;
    my %timestamp_hash;
SEVERITY_LEVEL_LOOP:
    foreach my $severity_level ( @severity_levels ) {
	my $timestamp_keyname = "time_severity_" . $severity_level;
	my @tickets = &get_tickets_from_cache($severity_level);
	next unless @tickets;

	foreach my $filename ( @tickets ) {
        # max tickets to process.
		my $max_tic_to_process;
        if ( $test_mode ) {
			$max_tic_to_process = $config{'TEST_TICKETS.tickets_to_test'};
        } else {
			$max_tic_to_process = $config{'TNE.max_tickets_per_run'};
		}

	    &write_log(7, "Processing file: [$filename]");
	    &write_log(7, "tickets_sent_this_hour=[" . $state->param('tickets_sent_this_hour') . "]");
	    &write_log(7, "max_tickets_per_run=[" . $max_tic_to_process . "]");

	    ### Throttling logic
	    if ( $state->param('tickets_sent_this_hour') >= $max_tic_to_process ) {
		unless ( &adjust_state_hour() ) {
		    ### Exceeded max_tickets_per_run limit. Bail out.
		    &write_log(4, "ERROR: Reached maximum number of tickets to send this hour.");
		    ### return 0;
		    $can_send_more_tickets = 0;
		    last SEVERITY_LEVEL_LOOP;
		}
	    }
	    
	    &write_log(6, "tickets_sent_this_hour=[" . $state->param('tickets_sent_this_hour') . "]");

	    my $hashref;
	    eval {
		$hashref = retrieve($filename);
	    };
	    if ( $@ ) {
		my $message = qq{ERROR: While retrieving [$filename][$@]};
		&write_log(0, $message);
		next;
	    }

	    ### Retrieve OPERATING_SYSTEM and LAST_LOGGED_ON_USER if needed.
	    unless ( $hashref->{'OPERATING_SYSTEM'} && $hashref->{'LAST_LOGGED_ON_USER'} ) {
		### Retrieve additional fields: Operating System and Last Logged on User.
		$operating_system = undef;
		$last_logged_on_user = undef;
        # set $qid to current VULNINFO/QID for parser to parse other values for this qid
        $qid = $hashref->{'VULNINFO/QID'};
        $ticket_number = $hashref->{'NUMBER'}; 
		next unless &get_additional_fields( $hashref->{'DETECTION/IP'} );
        
		if ( $operating_system || $last_logged_on_user ) {
		    $hashref->{'OPERATING_SYSTEM'} = $operating_system if $operating_system;
		    $hashref->{'LAST_LOGGED_ON_USER'} = $last_logged_on_user if $last_logged_on_user;
		    
		    &Storable::store( $hashref, $filename );
		}
	    }

	    my $successful_transmission = 0;
	    my $protocol = uc($config{'CUSTOMER.protocol'});
	    &write_log(7, "\$protocol=[$protocol]");
	    for ( my $attempt = 0; $attempt < $config{'QG.max_transmission_attempts'}; $attempt++ ) {
		if ( $protocol eq 'POSTEMSG' ) {
		    $successful_transmission = &send_im_data_postemsg($hashref);
		} elsif ( $protocol eq 'SMTP' ) {
		    $successful_transmission = &send_im_data_smtp($hashref);
		} else {
		    $successful_transmission = &send_im_data_opal($hashref);
		}
		if ( defined $config{'TNE.sleep_between_sends'} ) {
		    sleep( $config{'TNE.sleep_between_sends'} );
		}
        # increase the success ticket transmission count by one.
		$success_count = $success_count + 1;
		&write_log(6, "\$successful_transmission=[$successful_transmission]"); ### DEBUG
		last if $successful_transmission;

		my $message = "ERROR: Could not transmit ticket number ";
		$message .= $hashref->{'NUMBER'};
		$message .= " after " . ( $attempt + 1 ) . " attempt";
		$message .= $attempt ? "s." : ".";
		&write_log(1, $message);
	    }

	    &write_log(7, "Transmission success=[$successful_transmission]"); ### DEBUG

	    if ( $successful_transmission ) {
		### Successfully transmitted ticket.

		### Update the latest timestamp for this severity level, if needed.
		if (
		    ( &tne_datediff($state->param($timestamp_keyname), $hashref->{'LATEST_DATETIME'}) < 0  )
		    &&
		    (
		     (! defined $timestamp_hash{$timestamp_keyname} )
		     ||
		     ( &tne_datediff($timestamp_hash{$timestamp_keyname}, $hashref->{'LATEST_DATETIME'}) < 0 )
		     )
		    ) {
		    &write_log(7, "Setting \$timestamp_hash{$timestamp_keyname}=[" . $hashref->{'LATEST_DATETIME'} . "]" );
		    $timestamp_hash{$timestamp_keyname} = $hashref->{'LATEST_DATETIME'};
		}

		unless ( $state->param('tickets_sent_this_hour') == $max_tic_to_process ) {
		    $state->param('tickets_sent_this_hour', $state->param('tickets_sent_this_hour') + 1);
		    $state->save();
		}


		### Delete the file
		if ( unlink $filename ) {
		    &write_log(7, "Deleted [$filename]");
		    &write_log(7, "BEFORE tickets_in_cache=[" . $state->param('tickets_in_cache') . "]" );
			
		    ### Decrement tickets in cache.
		    $state->param('tickets_in_cache', $state->param('tickets_in_cache') - 1);
		    $state->save();
		    &write_log(7, "AFTER tickets_in_cache=[" . $state->param('tickets_in_cache') . "]" );
		} else {
		    &write_log(1, "ERROR: Could not delete [$filename][$!]");
		}
	    } else {
		### Could not transmit ticket. Do error-handling.
		my $message = "ERROR: Could not transmit ticket number ";
		$message .= $hashref->{'NUMBER'};
		$message .= " even after ";
		$message .= $config{'CUSTOMER.max_transmission_attempts'};
		$message .= " attempts.";
		$failure_count = $failure_count + 1;
		$failure_msg .= $message . "\n";	
		&write_log(1, $message);
	    }
	}
    } ### foreach @severity_levels

    ### Write the updated timestamps to disk.
    foreach my $key ( keys %timestamp_hash ) {
	### Decrement the timestamp by one second, to handle boundary conditions.

	my $str = $timestamp_hash{$key};
	$state->param($key, $str );
	&write_log(7, "Setting state: $key=[$str]" );
    }

    $state->save();
    return $can_send_more_tickets;
}

##################################################################

sub send_im_data_postemsg {
    ### Post some data to customers using the POSTEMSG protocol.

    my ( $hashref ) = @_;

    ### Verify that at least one POSTEMSG connection parameter is defined.
    my $found_postemsg_param;
    foreach my $postemsg_param ( qw(POSTEMSG.postemsg_server POSTEMSG.postemsg_conf_file) ) {
	if ( ( ! ref($config{$postemsg_param}) ) && $config{$postemsg_param} ) {
	    $found_postemsg_param++;
	    last;
	}
    }

    unless ( $found_postemsg_param ) {
	my $message = "ERROR: Please specify either postemsg_server or postemsg_conf_file in the config file.";
	&write_log(0, $message);
	return 0;
    }

    my $command = $config{'POSTEMSG.postemsg'};

    if ( $config{'POSTEMSG.postemsg_server'} && (! ref($config{'POSTEMSG.postemsg_server'}) ) ) {
	$command .= q{ -S } . $config{'POSTEMSG.postemsg_server'};
    } else {
	$command .= q{ -f } . $config{'POSTEMSG.postemsg_conf_file'};
    }


    my $resolver_info = "LAST_LOGGED_ON_USER=" . $hashref->{'LAST_LOGGED_ON_USER'};
    $resolver_info .= " HOST=" . $hashref->{'DETECTION/DNSNAME'};
    $resolver_info .= "(" . $hashref->{'DETECTION/NBHNAME'} . "):";
    $resolver_info .= $hashref->{'DETECTION/IP'};
    $resolver_info .= " OS='" . $hashref->{'OPERATING_SYSTEM'} . "'";
    $resolver_info .= " QID=" . $hashref->{'VULNINFO/QID'};
    $resolver_info .= " RESOLUTION='" . $hashref->{'DETAILS/SOLUTION'} . "'";

    $command .= q{ -m };
    $command .= &html_to_text( &shell_escape($resolver_info) );
    $command .= " \\\n";

    ### Get the event_class from the rule map.
    my $latest_rule =  (split /\,/, $hashref->{'RULE'})[0];
    my $event_class = $rule_map{"default." . $latest_rule} || $rule_map{'default.DEFAULT'};

    &write_log(7, "\$latest_rule=[$latest_rule]"); ### DEBUG
    &write_log(7, "\$event_class=[$event_class]"); ### DEBUG
    &write_log(7, "\$rule_map{$latest_rule}=[" . $rule_map{$latest_rule} . "]"); ### DEBUG

    $command .= 'QUALYS_TICKET_NUMBER=' . $hashref->{'NUMBER'} . ' ';
    $command .= "RULE=";
    $command .= &shell_escape($latest_rule);
    $command .= " $event_class ";
    $command .= $config{'POSTEMSG.event_source'};

    &write_output("$command\n\n") if $write_output;

    my $output = qx($command); ### DEBUG
    my $return_code = $? >> 8;
    my $result;

    if ( $output || $return_code ) {
	$result = 0;
	&write_log(3, "ERROR: Received the following message from POSTEMSG [$output]") if $output;
	&write_log(3, "ERROR: Received the following return code from POSTEMSG [$return_code]") if $return_code;
    } else {
	$result = 1;
    }

    return 1;
    ### return $result;
 
}

##################################################################

sub send_im_data_smtp {
    ### Post some data to customers using the SMTP protocol.

    my ( $hashref ) = @_;
    my ( $smtp );
    my $template_file = &format_file($hashref);
    my $subj_temp;
    my $body_temp;
    if ($template_file =~ m/^.+?\[SUBJECT\](.+)\[BODY\](.+)/s){
       $subj_temp = $1;
       $body_temp = $2;
    }
    $subj_temp =~ s/^\s+//s;
    $subj_temp =~ s/\s+$//s;
    # subject for the testing
    $subj_temp.= '(Testing email)' if $test_mode;
	$smtp = &check_for_smtp($config{'SMTP.host'});
	if ((! defined $smtp)){
	my $message = "ERROR: while getting SMTP connection [$@] SMTP.host";
	&write_log(1, $message);
	die("$message\n");
    } else {

	eval {
	    my $from_email;
        if ($test_mode) {
			$from_email = $config{'TEST_TICKETS.from'};
		} else {
		 	$from_email = $config{'CUSTOMER_EMAIL.from'};
		}
        	&write_log(7, "from email is [$from_email]\n");
	    	$smtp->mail($from_email);
		my $recipients;
        if ($test_mode) {
        	 $recipients = $config{'TEST_TICKETS.to'};
		} else {
        	 $recipients = $config{'CUSTOMER_EMAIL.to'};
		}
        my @recipients;
	    #my @recipients = ref $config{'CUSTOMER_EMAIL.to'} ? @{ $config{'CUSTOMER_EMAIL.to'} } : split /\,/, $config{'CUSTOMER_EMAIL.to'};
        if (ref ($recipients)){
           @recipients = @{$recipients};
           $recipients = join (',', @recipients);
        } else {
           @recipients = split (',', $recipients);
        } 
	    my $recipients_message = q{Sending email to the following: [};
	    $recipients_message .= (join '|', @recipients);
	    $recipients_message .= ']';
	    &write_log(7, "recipents is [$recipients_message]\n");
	    $smtp->to(@recipients);
		print "$subj_temp ...\n";
	    $smtp->data();
	    $smtp->datasend("From: $from_email\n");
	    # bugzilla requires a To: field
	    $smtp->datasend("To: $recipients\n");

            $smtp->datasend("Subject: ".$subj_temp."\n");

	    $smtp->datasend("$body_temp\n");
	    $smtp->dataend();
	    $smtp->quit;
	};
	
	if ( $@ ) {
	    my $message = "ERROR: while sending email [$@]";
	    &write_log(3, $message);
	    return 0;
	}
    }

    return 1;

}

##################################################################

sub send_im_data_opal {
    ### Post some data to customer using the OPAL protocol.
    ### This subroutine will be implemented if needed.

    ###TO BE IMPLEMENTED
}

##################################################################

sub get_additional_fields {
    my ( $ip_address ) = @_;

    my ( $qg_service_name, $qg_params_hashref, $qg_xml );

    $qg_service_name = 'asset_range_info.php';
    $qg_params_hashref = { 'target_ips' => $ip_address };
    $qg_xml = &get_qg_data( $qg_service_name, $qg_params_hashref );

    unless ( length($qg_xml) > 10 ) {
	my $message = "ERROR: Did not receive a valid response from QualysGuard. [$qg_xml]";
	&write_log(2, $message);
	return;
    }

    ### &write_log(7, "XML from [$qg_service_name]\n$qg_xml");
    &parse_qg_data( $qg_service_name, $qg_xml );
    #&glossary_handler($qg_xml);
    # Process using the glossary_twig_handler since the old one is buggy.
    &glossary_twig_handler($qg_xml);
    &write_log(7, "Parsed XML from $qg_service_name");

    return 1;
}

##################################################################

sub get_tne_state {
    ### Get the state of the application.
    ### The state is a set of key/value pairs,

    my @state_path = ( $_[0],  '../state.conf', './state.conf' );

    foreach my $state_location ( @state_path ) {
	if ( -e $state_location ) {
	    $state_file = $state_location;
	    last;
	}
    }

    $state_file ||= './state.conf';

    my $recalculate_hour = 1;
    unless ( -e $state_file ) {

	my $days_ago = $config{'TNE.history_days'};
    my $modified_since_date = $config{'ATTRIBUTES.modified_since_datetime'};

	my $init_time;
    if (!(ref ($modified_since_date))){
     $init_time = $modified_since_date;
    } elsif (!(ref ($days_ago))){
     $init_time = &tne_time2str(time - $days_ago * 86400 );
    } else {
     $init_time = '1970-01-01';
    }

	my %default_params = (
			      'tickets_in_cache' => 0,
			      'tickets_sent_this_hour' => 0,
			      'this_hour' => (localtime)[2],
			      'today' => &get_date(),
			      'time_severity_NULL' => $init_time,
			      'time_severity_1' => $init_time,
			      'time_severity_2' => $init_time,
			      'time_severity_3' => $init_time,
			      'time_severity_4' => $init_time,
			      'time_severity_5' => $init_time
			      );
	return 0 unless &init_state_file( \%default_params );
	$recalculate_hour = 0;
    }

    $state = new Config::Simple($state_file);

    &adjust_state_hour() if $recalculate_hour;

    return 1;
}

##################################################################

sub get_rule_map {
    ### Get the rule map.
    ### The rule map is a set of key/value pairs.
    ### Each key is a rule that might be associated with a ticket.
    ### Each value is the qualys_event_class that should be sent
    ### to customer for that rule.

    my $rule_file;
    my @rule_path = ( $_[0],  '../conf/rule_map.conf', './rule_map.conf' );

    foreach my $rule_location ( @rule_path ) {
	if ( -e $rule_location ) {
	    $rule_file = $rule_location;
	    last;
	}
    }


    if ( -e $rule_file ) {
	eval {
	  Config::Simple->import_from($rule_file, \%rule_map);	
	};
	if ( $@ ) {
	    &write_log(0, "ERROR: Could not read rule map file: [$rule_file][" . $@ . "]");
	} else {

	    foreach my $event_class ( keys %rule_map ) {
		&write_log(7, "\$rule_map{$event_class}='" . $rule_map{$event_class} . "';" ); ### DEBUG
	    }
	    return 1;
	}
    } else {
	&write_log(0, "ERROR: Could not read rule map file: [$rule_file][$!]");
    }

}


##################################################################

sub set_tne_state {
    ### Set the state of the application.

    my ( $hashref ) = @_;

    ### Set new params in a loop.
    foreach my $key ( keys %{$hashref} ) {
	$state->param( $key, $hashref->{$key} );
    }

    my $backup_state_file = "$state_file.bak";
    $state->write($backup_state_file);

    unless ( rename( $backup_state_file, $state_file ) ) {
	my $message = "ERROR: Could not rename state file from $backup_state_file to $state_file [$!]\n";
	&write_log( 0, $message );
    }

}

##################################################################

sub init_state_file {
    ### Initialize state file
    ### Config::Simple claims to do this automatically, but throws warnings.

    my ( $hashref ) = @_;

    unless ( -e $state_file ) {
	if ( open(STATE_FILE, ">$state_file") ) {

	    ### Set new params in a loop.
	    foreach my $key ( keys %{$hashref} ) {
		print STATE_FILE $key, '=', $hashref->{$key}, "\n";
	    }

	    close(STATE_FILE);
	} else {
	    my $message = "ERROR: Could not create state file [$state_file][$!]\n";
	    &write_log( 0, $message );
	    return 0;
	}
    }

}

##################################################################

sub tne_datediff {
    ### Compute the difference between two dates.
    ### The dates could be in either UNIX seconds,
    ### or as formatted time strings.
    ### Returns the number of seconds between the dates.

    my ( @dates ) = @_[0,1];
    my ( @times ) = map { /^\d+$/ ? $_ : &tne_str2time($_) } @dates;
    my $result = $times[0] - $times[1];

    return $result;
}

##################################################################

sub tne_str2time {
    ### Convert QG-style date-time string to UNIX time.
    ### for example: 2006-11-27T21:39:34Z => 1164692374

    my ( $string ) = @_;

    my $time_str = str2time($string);
    $time_str += 28800; ### workaround for Date::Parse

    return $time_str;
}

##################################################################

sub tne_time2str {
    ### Convert UNIX time to a QG-style date-time string.
    ### for example: 1164692374 => 2006-11-27T21:39:34Z

    my ( $time_str ) = @_;
    my ($ss,$mm,$hh,$day,$month,$year,$zone) = (localtime($time_str))[0..5,8];
    $month++;
    $year += 1900;

    my $date_str = sprintf "%4d-%02d-%02dT%02d:%02d:%02dZ" , $year, $month, $day, $hh, $mm, $ss;

    return $date_str;

}

##################################################################

sub initialize {

    ### Read command-line options.
    &read_options();

    ### Read Configuration.
    return 0 unless &read_config();

    ### some validation for the values in config file
    &validate_data();

    ### Create required directories
    my $directory_create_succeeded = &create_directory_structure();

    unless ( $directory_create_succeeded ) {
	my $message = q{ERROR: Could not create necessary directories. Aborting.};
	&write_log(0, $message);
	return 0;
    }
    &write_log(7, "Created necessary directories.");

    ### Try to create and lock the lockfile.
    return 0 unless &tne_lock();

    return 0 unless &get_tne_state();
    &write_log(7, "Read state");

    if ( uc($config{'CUSTOMER.protocol'}) eq 'SMTP' ) {
	&write_log(7, "Skipping rule map");
    } else {
	if ( &get_rule_map() ) {
	    &write_log(7, "Read rule map");
	} else {
	    my $message = "ERROR: Could not read rule_map. Exiting.";
	    &write_log(0, $message);
	    return 0;
	}
    }


    return 1;
}

##################################################################

sub adjust_state_hour {

    ### This subroutine checks to see if the current hour is
    ### different from the one stored in the state file.
    ### If so, it adjusts the hour in the state file.
    ### Also, it zeroes out the tickets_sent_this_hour.
    ### If the state file needed to be modified, it returns a 1,
    ### otherwise it returns a 0.

    my $hour_adjusted = 0;
    my $hour_now = (localtime)[2];
    my $today = &get_date();

    if (
	( $state->param('this_hour') != $hour_now )
	||
	( $state->param('today') ne $today )
	) {

	### an hour must have rolled over,
	### or it's the same hour on a different day.

	$state->param('tickets_sent_this_hour', 0);
	$state->param('this_hour', $hour_now);
	$state->param('today', $today);
	$state->save();
	$hour_adjusted = 1;
    }

	### make sure tickets_in_cache in state file and number of files in cache dir are same. If not update state file with number of files in cache dir
	my $total_count;
	$total_count = &get_files_count();
	my $old_value = $state->param('tickets_in_cache');
	if ($total_count != $state->param('tickets_in_cache')){
		$state->param('tickets_in_cache', $total_count);
    	$state->save();
		my $new_value = $state->param('tickets_in_cache');
		&write_log(6, "tickets_in_cache in state file was $old_value. Total number of files in cache dir are $total_count. Updated state file to $new_value");
	}
    return $hour_adjusted;

}

##################################################################

sub get_files_count (){
	my $total_count;
	$total_count = 0;
	foreach my $i(0..5){
	my $dir = "cache/$i";
	my @files = <$dir/*>;
	my $count = @files;
	$total_count += $count;
	}
	return $total_count;
}


##################################################################


##################################################################

sub create_directory_structure {
    ### Create directories needed by TNE.

    my $final_result = 1;
    
    # if this runs with --test-mode option, it stores tickets 
	# in test directory

   	if ($test_mode) {
        unless ( -d $test_dir ){
			unless (mkdir($test_dir)){
		    die "Could not make $test_dir directory: [$!]";
		    return 0;
			}
		}
		unless ( chdir($test_dir) ){
		    die "Could not change to $test_dir directory: [$!]";
		    return 0;
		}
	}
    foreach my $dir ( qw(TNE.log_dir TNE.cache_dir) ) {
	my $directory_name = $config{$dir};
	if ( -d $directory_name ) {
	    &write_log(7, "Directory already exists: [$directory_name]");

	    if ( $dir eq 'TNE.cache_dir' ) {
		foreach my $severity_level ( @severity_levels ) {
		    my $subdir = "$directory_name/$severity_level";
		    if ( -d $subdir ) {
			&write_log(7, "Directory already exists: [$subdir]");
		    } else {
			my $sub_result = &make_dir($subdir);
			if ( $sub_result == 0 ) {
			    &write_log(1, "Could not create directory: [$subdir][$!]");
			    die "Could not create directory: [$subdir][$!]";
			    return 0;
			} else {
			    &write_log(7, "Created directory: [$subdir]");
			}
		    }
		}
	    }
	} else {
	    my $result = &make_dir($directory_name );
	    if ( $result ) {
		&write_log(7, "Created directory: [$directory_name]");
		if ( $dir eq 'TNE.cache_dir' ) {
		    foreach my $severity_level ( @severity_levels ) {
			my $subdir = "$directory_name/$severity_level";
			my $sub_result = &make_dir($subdir);
			if ( $sub_result == 0 ) {
			    &write_log(1, "Could not create directory: [$subdir][$!]");
			    return 0;
			} else {
			    &write_log(7, "Created directory: [$subdir]");
			}
		    }
		}
	    } else {
		&write_log(1, "Could not create directory: [$directory_name][$!]");
		die "Could not create directory: [$directory_name][$!]";
		return 0;
	    }
	}
    }

    return $final_result;

}

##################################################################

sub clear_dir {
    ### Deletes all files from a given directory,
    ### but does not delete the directory.

    my ( $dir ) = @_;

    unless ( unlink( <"$dir/*"> ) ) {
	my $message = qq{ERROR: While deleting files from $dir [$!]};
	&write_log(1, $message);
	return 0;
    } else {
	return 1;
    }

}

##################################################################

sub make_dir {

    my ( $directory_name ) = @_;
    my $result = 1;

    unless ( mkdir $directory_name ) {
	my $message = qq{ERROR: Could not create directory [$directory_name][$!]};
	&write_log(0, $message);
	$result = 0;
    } else {
	&write_log(7, "Created [$directory_name]");
    }

    return $result;

}

##################################################################

sub shell_escape {
    ### This subroutine takes a string, and escapes any
    ### characters that might confuse a Linux shell.
    ### The resulting string is enclosed in double-quotes.

    my ( $value ) = @_;

    $value =~ s/(['"!#])/\\$1/g;
    $value =~ s/\s/ /g;
    $value = '"' . $value . '"';

    return $value;
}

##################################################################

sub tne_lock {
    ### Creates and locks a file.

    &write_log(7, "Now attempting to lock [" . $config{'TNE.lock_file'} . "]");
    $lockmgr = LockFile::Simple->make(
				      -autolean => 1,
				      -format => '%f',
				      -max => 1
				      );

    if ( $lockmgr->lock($config{'TNE.lock_file'}) ) {
	&write_log(7, "Locked [" . $config{'TNE.lock_file'} . "]" );
	$got_lock = 1;
    } else {
	my $message = "Another identical process is running. Please delete the lockfile [" . $config{'TNE.lock_file'} . "] and try again.\n";
	&write_log(6, $message);
	print $message;
	return 0;
    }

    unless ( -e $config{'TNE.lock_file'} ) {
	&write_log(0, "ERROR: lock file does not exist [" . $config{'TNE.lock_file'} . "]" ); ### DEBUG
	return 0;
    }

    return 1;

}

##################################################################

sub tne_unlock {

    ### Release locks
    if ( $lockmgr->unlock($config{'TNE.lock_file'}) ) {
	&write_log(7, "Unlocked lock file: [" . $config{'TNE.lock_file'} . "]" ); ### DEBUG

	if ( -e $config{'TNE.lock_file'} ) {
	    &write_log(1, "ERROR: lock file [" . $config{'TNE.lock_file'} . "] exists after being unlocked." ); ### DEBUG
	}
    } else {
	&write_log(1, "ERROR: Could not unlock file [" . $config{'TNE.lock_file'} . "][$!]");
    }

}

##################################################################

sub get_date {
    ### Returns the date in a YYYY/MM/DD format.

    my $time = $_[0] || time;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
    $year += 1900;
    $mon++;

    my $today = sprintf "%4d/%02d/%02d", $year, $mon, $mday;

    return $today;

}

##################################################################

sub get_syslog_time {
    ### Returns the timestamp in a YYYY/MM/DD HH:MM:SS format.

    my $time = $_[0] || time;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
    $year += 1900;
    $mon++;

    my $now = sprintf "%4d/%02d/%02d %02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec;

    return $now;

}
##################################################################

sub html_to_text {
    ### Remove HTML tags, but extract and include URL's from hyperlinks.

    my ( $html ) = @_;
    $html =~ s/\s+/ /g;
    $html =~ s/< *A[^>]+HREF *= *\\?["']([^"'\\]+)\\?["'][^>]*>([^<]+)< *\/ *A *>/$2 ( $1 )/gi;
    $html =~ s/<LI>/ * /gi;
    $html =~ s/<[^>]+>//g;
    $html =~ s/ +/ /g;
    $html =~ s/&quot;/\\"/gi;
    $html =~ s/&amp;/&/gi;

    return $html;
}

##################################################################

END {
    &tne_unlock() if $got_lock;
}

##################################################################

sub show_usage {

    print "\n\n";

    print qq{
      USAGE:

	$0 [options]

      OPTIONS:

	--help : Show this help page.

	--write-output : Write an output file in the same directory as the log file.
	                 This file contains a list of commands

	--retrieve-only : Retrieve tickets from QualysGuard and cache them,
			  but do not send to customer ticketing application.

	--send-cached : Send tickets from cache, retrieving additional	              
		        fields from QualysGuard if needed.

	--test-mode : To see if the format specified is correct.

    };

    print "\n\n";

}

##################################################################

sub read_options {
    ### This subroutine reads command-line options, and sets
    ### some global variables.

    my $result = GetOptions(
			    "help|h" => \$help,
			    "write-output" => \$write_output,
			    "retrieve-only" => \$retrieve_only,
			    "test-mode" => \$test_mode,
			    "send-cached" => \$send_cached
			    );

}

##################################################################

sub get_tickets_from_cache {
    ### Returns a list of all cached tickets for a given severity level.

    my $severity_level = shift;
    my $directory =  $config{'TNE.cache_dir'} . "/" . $severity_level;
    &write_log(7, "Directory: [$directory]");

    my @tickets;
    if ( opendir(D, $directory) ) {
	### Select files from directory entries.
	my @directory_entries = readdir(D);
	closedir(D);

	foreach my $dir_entry ( sort @directory_entries ) {
	    my $full_dir_entry = "$directory/$dir_entry";
	    if ( -f $full_dir_entry ) {
		push @tickets, $full_dir_entry;
	    }
	}

	&write_log(7, "Opened directory: [$directory] and read " . scalar(@tickets) . " tickets." );
    } else {
	my $message = qq{ERROR: Could not open directory [$directory][$!]\n};
	&write_log(1, $message);
    }

    return @tickets;
}

###################################################################

sub format_file () {
        my $hashref = shift;
        my ($template);
        my ($template_file) = $config{'TEMPLATE.file'};
           $template = Text::Template->new(TYPE => 'FILE', SOURCE => $template_file) or die "Couldn't construct template: $Text::Template::ERROR";

	    while ( my ($key, $value) = each (%asset_range_info)) {
		unless ($value =~ /[0-9A-Za-z!@#$%^&*()\-+\[\]]/){
        $value = "N/A";
        #next;
        }
        $value = &shell_escape($value);
        $value =~ s/^\"\s*//g;
        $value =~ s/\s*\"$//g;
		$asset_range_info{$key} = $value;
        } # while
        my %var = (tic_num => $hashref->{'NUMBER'}, tic_date => $hashref->{'CREATION_DATETIME'}, tic_state => $hashref->{'CURRENT_STATE'}, tic_assignee_email => $hashref->{'ASSIGNEE/EMAIL'}, tic_assignee_login => $hashref->{'ASSIGNEE/LOGIN'}, tic_det_ip => $hashref->{'DETECTION/IP'}, tic_det_dns => $hashref->{'DETECTION/DNSNAME'}, tic_det_nbh => $hashref->{'DETECTION/NBHNAME'}, tic_det_port => $hashref->{'DETECTION/PORT'}, tic_det_service => $hashref->{'DETECTION/SERVICE'}, tic_det_protocol => $hashref->{'DETECTION/PROTOCOL'}, tic_det_fqdn => $hashref->{'DETECTION/FQDN'}, tic_det_ssl => $hashref->{'DETECTION/SSL'}, tic_vuln_type => $hashref->{'VULNINFO/TYPE'}, tic_vuln_qid => $hashref->{'VULNINFO/QID'}, tic_vuln_sev => $hashref->{'VULNINFO/SEVERITY'}, tic_vuln_st_sev => $hashref->{'VULNINFO/STANDARD_SEVERITY'}, tic_det_dia => $hashref->{'DETAILS/DIAGNOSIS'}, tic_det_cons => $hashref->{'DETAILS/CONSEQUENCE'}, tic_det_sol => $hashref->{'DETAILS/SOLUTION'}, tic_det_result => $hashref->{'DETAILS/RESULT'}, host_ip => $asset_range_info{host_ip}, host_trac_meth => $asset_range_info{host_trac_meth}, host_dns => $asset_range_info{host_dns}, host_netbios => $asset_range_info{host_netbios}, host_op_sys => $asset_range_info{host_op_sys}, asset_gr_title => $asset_range_info{host_asset_gr_title}, vuln_det_qid_cont => $asset_range_info{glos_qid_con}, vuln_det_qid_id => $asset_range_info{glos_qid_id}, vuln_det_qid_title => $asset_range_info{glos_title}, vuln_det_qid_sev => $asset_range_info{glos_sev}, vuln_det_qid_cat => $asset_range_info{glos_cat}, vuln_det_qid_cus => $asset_range_info{glos_cust}, vuln_det_qid_threat => $asset_range_info{glos_threat}, vuln_det_qid_impact => $asset_range_info{glos_impact}, vuln_det_qid_sol => $asset_range_info{glos_sol}, vuln_det_qid_comp => $asset_range_info{glos_comp}, vuln_det_qid_update => $asset_range_info{glos_update}, vuln_det_qid_cvss_temp => $asset_range_info{glos_cvss_tem}, vuln_det_qid_cvss_base => $asset_range_info{glos_cvss_base}, vuln_det_qid_vend_id => $asset_range_info{glos_vend_id_url}, vuln_det_qid_cve_id => $asset_range_info{glos_cve_id_url}, vuln_det_qid_bug_id => $asset_range_info{glos_bugtraq_id_url}, vuln_info_qid => $asset_range_info{vuln_info_qid}, vuln_info_type => $asset_range_info{vuln_info_type}, vuln_info_port => $asset_range_info{vuln_info_port}, vuln_info_service => $asset_range_info{vuln_info_service}, vuln_info_fqdn => $asset_range_info{vuln_info_fqdn}, vuln_info_protocol => $asset_range_info{vuln_info_protocol}, vuln_info_ssl => $asset_range_info{vuln_info_ssl}, vuln_info_result => $asset_range_info{vuln_info_result}, vuln_info_fir_found => $asset_range_info{vuln_info_fir_found}, vuln_info_las_found => $asset_range_info{vuln_info_las_found}, vuln_info_times_found => $asset_range_info{vuln_info_times_found}, vuln_info_status => $asset_range_info{vuln_info_status}, vuln_info_tic_num => $asset_range_info{vuln_info_tic_num}, vuln_info_tic_state => $asset_range_info{vuln_info_tic_state}, cvss_base_score_source => $asset_range_info{cvss_base_score_source}, tic_assignee_name => $hashref->{'ASSIGNEE/NAME'}, tic_vuln_title => $hashref->{'VULNINFO/TITLE'}, rule => $hashref->{'RULE'}, qg_severity => $hashref->{'VULNINFO/SEVERITY'});
        my $result_from_template = $template->fill_in(HASH => \%var);
        return $result_from_template;
        
}

sub validate_data () {
	### check for valid emails
	my %to_emails = ('TEST_TICKETS.to' => $config{'TEST_TICKETS.to'},
					'ADMIN_EMAILS.admins' => $config{'ADMIN_EMAILS.admins'},
					'CUSTOMER_EMAIL.to' => $config{'CUSTOMER_EMAIL.to'}
					);
	while ( my ($key, $value) = each (%to_emails)){
		if ( ref($value)){
			my @recipients; 
			@recipients	= @{$value};
			foreach my $e_mail(@recipients){
				next if $e_mail =~ m/^\s*$/;
				&validate_email($key, $e_mail);
			} # foreach
		} else {
			&validate_email($key, $value);
		} # if else
	}# while

	### check for max chars for vuln_title_contains,vuln_details_contains,vendor_ref_contains in config file
	my %text_att = ('vuln_title_contains' => $config{'ATTRIBUTES.vuln_title_contains'},
					'vuln_details_contains' => $config{'ATTRIBUTES.vuln_details_contains'},
					'vendor_ref_contains' => $config{'ATTRIBUTES.vendor_ref_contains'},
					'dns_contains' => $config{'ATTRIBUTES.dns_contains'},
					'netbios_contains' => $config{'ATTRIBUTES.netbios_contains'});
	while( my ($key, $value) = each (%text_att)){
        if ( ! ref($value)){
			&check_length($key, $value);
		}
	}

	### check for only numbers or - in attributes ticket_numbers,until_ticket_number,ips,qids,potential_vuln_severities
	
	my %num_att = ('ticket_numbers' => $config{'ATTRIBUTES.ticket_numbers'},
					'until_ticket_number' => $config{'ATTRIBUTES.until_ticket_number'},
					'ips' => $config{'ATTRIBUTES.ips'},
					'qids' => $config{'ATTRIBUTES.qids'},
					'potential_vuln_severities' => $config{'ATTRIBUTES.potential_vuln_severities'}	
					);
	while( my ($key, $value) = each (%num_att)){
		&validate_for_num($key,$value);	
	}

	### check for date format
	my %date_format = ('modified_since_datetime' => $config{'ATTRIBUTES.modified_since_datetime'},
                    'unmodified_since_datetime' => $config{'ATTRIBUTES.unmodified_since_datetime'}
                    );
	while( my ($key, $value) = each (%date_format)){
        &validate_date_format($key,$value);
    }

	### check for either 0 or 1 in invalid and overdue attributes.
	my %zero_one = ('overdue' => $config{'ATTRIBUTES.overdue'},
                    'invalid' => $config{'ATTRIBUTES.invalid'}
                    );
    while( my ($key, $value) = each (%zero_one)){
        &check_zero_one($key,$value);
    }

	### check for attribute states in conf file
	my $states_val = $config{'ATTRIBUTES.states'};
	&check_states($states_val);
}

sub check_states () {
	my $states_value = $_[0];
	if (ref $states_value){
		my @states_value = @{$states_value};
		foreach my $state (@states_value){
			next if $state =~ m/^\s*$/;
			if ($state !~ m/^\s*(OPEN|RESOLVED|CLOSED|IGNORED)\s*$/i){
				die ("$state is not valid value. states in the conf file should be one of these OPEN,RESOLVED,CLOSED,IGNORED.\n");
			} # if
		}# foreach
	}else {
		if ($states_value !~ m/^\s*(OPEN|RESOLVED|CLOSED|IGNORED)\s*$/i){
                die ("$states_value is not valid value. states in the conf file should be one of these OPEN,RESOLVED,CLOSED,IGNORED.\n");
		} # if
	}

}

sub check_zero_one () {
	my $att = $_[0];
    my $att_value = $_[1];
	if (! ref ($att_value)){
		if (($att_value ne 0) && ($att_value ne 1)){
        die ("$att in the conf file should be either 0 or 1.\n");
    }
	}
}

sub validate_date_format () {
	my $att = $_[0];
    my $att_value = $_[1];
	if (! ref ($att_value)){
	if (($att_value !~ m/^\s*\d\d\d\d-\d\d-\d\d\s*$/) && ($att_value !~ m/^\s*\d\d\d\d-\d\d-\d\dT\d\d\:\d\d\:\d\dZ\s*$/)){
		die ("$att_value for $att in the conf file is not a valid value.\n");	
	}
	}
}

sub validate_for_num () {
    my $att = $_[0];
	my $att_value = $_[1];
	if ( ref($att_value)){
		my @att_value; 
		@att_value	= @{$att_value};
		foreach my $value(@att_value){
                 #printf " Attribute " . $att. " " ;
                 #printf " Value " . $value . "\n" ;
		next if $value =~ m/^\s*$/;
		if (($att eq 'ticket_numbers') && ($value !~ m/^[\d\-]*$/)){
			die ("$value for $att in the conf file is not a valid value.\n");
		} elsif (($att eq 'ips') && ($value !~ m/^[\d\-\.]*$/)){
            die ("$value for $att in the conf file is not a valid value.\n");
	 	} elsif ((($att eq 'qids') || ($att eq 'potential_vuln_severities')) && ($value !~ m/^[\d]*$/)){
            die ("$value for $att in the conf file is not a valid value.\n");
		}
		} # foreach
	} else {
		if (($att eq 'ticket_numbers') && ($att_value !~ m/^[\d\-]*$/)){
            die ("$att_value for $att in the conf file is not a valid value.\n");
        } elsif (($att eq 'ips') && ($att_value !~ m/^[\d\-\.]*$/)){
            die ("$att_value for $att in the conf file is not a valid value.\n");
		} elsif ((($att eq 'qids') || ($att eq 'potential_vuln_severities')) && ($att_value !~ m/^[\d]*$/)){
            die ("$att_value for $att in the conf file is not a valid value.\n");
        } elsif (($att eq 'until_ticket_number') && ($att_value !~ m/^[\d]*$/)){
			die ("$att_value for $att in the conf file is not a valid value.\n");
		}
	} # if else
}

sub validate_email () {
	my $att = $_[0];
    my $text = $_[1];

	next if $text =~ m/^\s*$/;
	if ($text !~ /[\w\-]+\@[\w\-]+\.[\w\-]+/) {
		if ($att =~ m/CUSTOMER_EMAIL/){
			die ("$text in $att in the conf file is Not a valid e-mail address.\n");
		} else {
    		warn "$text in $att in the conf file is Not a valid e-mail address.\n";
		}
	} 
}

sub check_length () {
    my $att = $_[0];
	my $text = $_[1];
	my $text_length = length($text);
    if ($text_length > 100) {
        die("$att in the conf file is more than 100 chars .\n");
    }
}

sub check_for_smtp () {
	my $host = shift;
	## try num of attempts to connect to mail server specified in conf
	my $i = 1;
	my $smtp;
	my $attempts;
	if ((ref($config{'SMTP.num_of_attempts'})) || ($config{'SMTP.num_of_attempts'} !~ m/^\d+$/)){
		$attempts = 3;
	} else {
		$attempts = $config{'SMTP.num_of_attempts'};
	}
	while ($i < $attempts){
		$smtp = Net::SMTP->new($host);
		if ((! defined $smtp)){
			$i++;
			if (!(ref $config{'SMTP.sleep_between_sends'}) && ($config{'SMTP.sleep_between_sends'} =~ m/^\d+$/) ) {
            sleep( $config{'SMTP.sleep_between_sends'} );
			}
		}else{
			last;
		}
	}
	return $smtp;
}

sub get_attributes (){
   	my ($qg_params_hashref, $severity_level) = @_; 
    my %attributes;

	while (my ($key, $value) = each (%config)){
		$attributes{$key} = $value if $key =~ m/ATTRIBUTES/;
	}
	while (my ($key, $value) = each (%attributes)){
	if (ref ($value)){
		my $count = @{$value};
		if ($count > 0){ # this means it is not empty field
			my $string = join(',',@{$value});
			$key =~ s/ATTRIBUTES\.//;
            # we send potential_vuln_severities only one at a time like vuln
            # severities. So handle this accordingly.
			if ($key =~ m/potential_vuln_severities/){
				if ( ($string =~ m/$severity_level/) && ( $severity_level ne 'NULL' )) {
				$qg_params_hashref->{'potential_vuln_severities'} = $severity_level;
                 next;
                } else {
                 next;
                }
            }
			$qg_params_hashref->{$key} = $string;
		} else { # count < 0
			next;
		}
	} else { # if not ref
		$key =~ s/ATTRIBUTES\.//;
        # since we are handling this in get_tne_state, no need to handle it here.
		if ($key =~ m/modified_since_datetime/){
    			next;
  		}
		if ($key =~ m/potential_vuln_severities/){
			if(( $severity_level ne 'NULL' ) && ($value =~ m/$severity_level/)) {
				$qg_params_hashref->{'potential_vuln_severities'} = $severity_level;
        		next;
        	} else {
     		next;
			}
		}
		$qg_params_hashref->{$key} = $value;
	}
	} # while
	
} 
42;
