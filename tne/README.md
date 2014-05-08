# TNE (Ticket Notification Engine)

Revision: 1.5 $

TNE implements a one-way flow of tickets from QualysGuard to any Ticketing application via SMTP (mail) protocol.

# Configure

To configure TNE, please follow the steps below.

## Dependencies

Ensure that the following Perl modules are installed:

* Date::Parse
* URI::Escape
* LWP::UserAgent
* Text::Template
* XML::Simple
* Net::SMTP
* Config::Simple
* LockFile::Simple
* XML::Twig
* Data::Dumper
* Storable
* Getopt::Long

For your convenience, a script is provided to install these modules using CPAN:

	/usr/local/qualys/tne/bin/module_installer.pl

## Install TNE

Install the TNE integration (if not already installed). The code is installed under:

	/usr/local/qualys/tne

Command to install:

	rpm -ivh TNE-x.y.z-n.rpm

Install the configuration files:

	rpm -ivh TNE_conf_smtp-x.y.z-n.rpm

## Configuration

Set up configuration files.

Copy the sample config and template files

	cd /usr/local/qualys/tne/conf
	cp sample.conf tne.conf
	cp sample.tmpl tne.tmpl

Edit the TNE configuration file:

	/usr/local/qualys/tne/conf/tne.conf
	
The tne.conf file contains various sections.

Here are some important parameters that you'll likely need
to change. The parameters are listed below by section.

    [TNE]
    ### Maximum number of tickets that TNE can send to TEC in a given hour.
    ### If QualysGuard has more than this number of tickets, an admin is alerted.
    max_tickets_per_run=3
    
    ### Maximum number of tickets that TNE should cache.
    ### Caveat: This is a soft-limit.
    ### It's possible that a request to QualysGuard will
    ### return a number of tickets that exceeds this threshold.
    ### In this case, all those tickets will be cached,
    ### and no further tickets will be request from QualysGuard
    ### untill all tickets in cache are sent to the ticketing application.
    max_tickets_to_cache=5
    
    ### Sleep this many seconds after sending each ticket to TEC
    sleep_between_sends=2
    
    ### When TNE is executed first,
    ### how many past days of tickets should be retrieved?
    history_days=2
    
    
    [TEST_TICKETS]
    ### tickets to test
    tickets_to_test=1
    
    ### test tickets to email to 
    to=user.a@xyz.com,user.b@xyz.com
    
    ### test tickets from email
    from=test.user@xyz.com
    
    
    [ADMIN_EMAILS]
    # SMTP mail server
    host=mail.xyz.com
    
    # admin to receive email messages
    admins=admin@xyz.com
    # from email address
    from=john.doe@xyz.com
    
    # notifications and statistic data
    notifications=on
    statistical_data=on
    
    [QG]
    # QualysGuard username and password
    username=
    password=
    
    # Retry attemps
    max_transmission_attempts=2
    
    [TEMPLATE]
    # template file to be used
    file=/usr/local/qualys/tne/conf/tne.tmpl
    
    [CUSTOMER]
    # Protocol to be used to send email to ticketing application
    protocol=SMTP
    
    [CUSTOMER_EMAIL]
    # From email address
    from=john.doe@xyz.com
    # To email address
    to=jane.doe@xyz.com
    
    [ATTRIBUTES]
    # Tickets with certain ticket numbers. Specify one or more ticket numbers and/or
    # ranges.Use a dash(-) to separate the ticket range start and end. Multiple
    # entries are comma seperated.
    ticket_numbers=
    
    # Tickets until a certain ticket number. Specify the highest ticket number
    # to be selected. Selected tickets will have numbers less than or
    # equal to the ticket number specified.
    until_ticket_number=
    
    # Tickets with a certain assignee. Specify the user login of an
    # active user account.
    ticket_assignee=
    
    # Tickets that are overdue or not overdue. When not specified, overdue and
    # non-overdue tickets are selected. Specify 1 to select only overdue tickets.
    # Specify 0 to select only tickets that are not overdue.
    overdue=
    
    # Tickets that are invalid or valid. When not specified, both valid and invalid
    # tickets are selected. Specify 1 to select only invalid tickets. Specify
    # 0 to select only valid tickets.
    # You can selecti invalid tickets owned by other users, not yourself.
    invalid=
    
    # Tickets with certain ticket state/status. Specify one or more state/status
    # codes. A valid value is OPEN(for state/status OPEN or OPEN?REOPENED),
    # RESOLVED (for state Resolved), CLOSED(for state CLOSED/FIXED) or
    # IGNORED(for state Closed/Ignored). Multiple entries are comma seperated.
    # To select ignored vulnerabilities on hosts, specify states=IGNORED.
    states=open
    
    # Tickets modified since a certain date/time. Specify a date (required) and
    # time (optional) since tickets were modified. Tickets modified on or after
    # the date/time are selected.
    # The start date/time is specified in YYYY-MM-DD[THH:MM:SSZ] format(UTC/GMT),
    # like "2006-01-01" or "2006-05-25T23:12:00Z".
    # If this is empty, then the tickets will be from the days ago which is
    # specified in history_days in this config file. If history_days is also
    # blank, then the tickets are from 1970-01-01.
    modified_since_datetime=2008-04-15
    
    # Tickets not modified since a certain date/time. Specify a date (required) and
    # time (optional) since tickets were not modified. 
    # Tickets not modified on or after the date/time 
    
    are selected.
    # The date/time is specified in YYYY-MM-DD[THH:MM:SSZ] format(UTC/GMT),
    # like "2006-01-01" or "2006-05-25T23:12:00Z".
    unmodified_since_datetime=
    
    # Tickets on hosts with certain IP addresses. Specify one or more IP
    # addresses and /or ranges. Multiple entries are comma seperated.
    ips=
    
    # Tickets on hosts with IP addresses which are defined in certain asset groups. 
    # Specify the title of one or more asset groups.
    # Multiple asset groups are comma seperated.
    # The title "ALL" may be specified to select all IP addresses in the user account
    asset_groups=
    
    # Tickets on hosts that have a DNS hostname which contains a certain
    # text string. Specify a text string to be used. This string may include
    # a maximum of 100 characters(ascii)
    dns_contains=
    
    # Tickets on hosts that have a NetBIOS hostname which contains a certain
    # text string. Specify a text string to be used. This string may include
    # a maximum of 100 characters(ascii)
    netbios_contains=
    
    # Tickets for potential vulnerabilities with certain severity levels.
    # Specify one or more severity levels. Multiple levels are comma seperated.
    potential_vuln_severities=
    
    # Tickets for vulnerabilities with certain QIDs(Qualys IDs). Specify one or more
    # QIDs. A maximum of 10 QIDs may be specified. Multiple levels are comma seperated.
    qids=
    
    # Tickets for vulnerabilities that have a title which contains a certain text
    # string. The vulnerability title is defined in the Knowledgebase. Specify a
    # text string.This string may include a maximum of 100 characters(ascii)
    vuln_title_contains=
    
    # Tickets for vulnerabilities that have vulnerability details which contains
    # a certain text string. Vulnerability details provide descriptions for
    # threat, impact, solution and results(scan test results, when available).
    # Specify a text string.This string may include a maximum of 100 characters(ascii)
    vuln_details_contains=
    
    # Tickets for vulnerabilities that have a vendor reference which contains
    # a certain text string. Specify a text string.This string may include a maximum 
    # of 100 characters (ascii)
    vendor_ref_contains=
    
### Configure TNE TEMPLATE file
( /usr/local/tne/conf/tne.tmpl )
tne.tmpl contains the values from Qualys Guard.
The values start with $. For example the value of ticket number is
$tic_num. If you want this value, just insert in [BODY] section like
{ $tic_num }. Make sure you include { and }.

One more example:

If you want the reverse value of QG severity or if you want to call with some
other name, it can be done like

my_severity_number = { if ($qg_severity == 5) {
     '1';
  }
}
or
my_severity_text = { if ($qg_severity == 5) {
     'blocker';
  }
}

Whatever you insert between [SUBJECT] and [BODY] will be taken as
subject for your email.
Whatever you insert below [BODY] will be taken as body for your email.

The text above [SUBJECT] is for your reference. 
###########################################################

5. To validate the template format, you can run tne.pl in a test mode

cd /usr/local/qualys/tne/bin
perl tne.pl --test-mode

This will generate one ticket and send it to the to: email specified in the
[TEST_TICKETS] section.


##########################################################

6. Change ownership to the user and group that TNE will
actually run as.

Ensure the user and group exists before running this command.
For example, if TNE will run as user: tne, group: root

chown -R tne:root /usr/local/qualys/tne

###########################################################

7. Create a scheduler entry for tne.pl
Insert the following in the crontab to run the tne script at 22:00hrs every day.

$crontab -e

00 22 * * * root /usr/bin/perl /usr/local/qualys/tne/bin/tne.pl >> /usr/local/qualys/tne/bin/logs/output.txt


###########################################################
