# Fetchreport perl script

Automatically Launch and Download Reports

(Tested with QualysGuard 6.23 and with perl 5.14.1 and 5.124)

## December 2011 updates

This is a major rewrite of this tool, hence moving to version 7_beta. We found issues with some proxies and decided to use WWW::Curl::Easy for the API request instead of LWP. It guarantees a better compatibility.

In addition, when a report takes too much time to be generated and to avoid potential session timeout when using session based authentication, the default authentication method is now BASIC.

Support of CSV reports has been also added and proxy authentication is now supported via the option:

	--proxy=http://PROXY_USER:PROXY_PASSWORD@PROXY_SERVER:PROXY_PORT

 

## August 2011 updates

This new version of the perl script “fetchreport.pl” provides the following new capabilities:

* Support of remediation reports
* Support of PDF report distribution list and password encryption
* Can only generate a report a leave it on in the QualysGuard report center (doesn’t download the report)
* Support for Basic Authentication to avoid potential session timeout when a proxy is used.
* Better troubleshooting with options –debug=y|yy
* Optimized DELAYs. Note: the DELAYs must be updated to reflect your subscription properties.

**Like any other API script written by Qualys and publicly available via the community or any other location, this fetchreport perl script should be considered as a beta version and it is not supported.**

**The purpose of such API prototypes is to demonstrate the API functionalities by providing useful examples.**

**User can run the script for their production needs at their own risks and we recommend that the code has been reviewed and customized before doing so.**

Qualys customers use the scanning functionality to easily identify systems and the vulnerabilities on those systems throughout their network. Customers have asked for a way to automatically launch and download scan reports.  This can be accomplished very easily using the fetchreport.pl script.

The fetchreport.pl script has been updated based on the Report Share functionality introduced with QualysGuard 5.1 and exposed through the API v2 framework. To run the new fetchreport.pl script, Report Share must be enabled in your account. Please contact Qualys if you would like to upgrade your account to use Report Share.

The fetchreport.pl script can be run on any system utilizing Perl and will output a complete QualysGuard report based on the parameters specified. The fetchreport.pl script can only download/generate reports that use automatic data selection not manual.  Manual reports require the user to select the scan results that should be used and therefore can not be fully automated.

Please Note: Before you begin, please find your QualysGuard API server URL. To run fetchreport.pl you must supply your API server URL as an input parameter on the command line. The API server URL to use depends on your account location.

**Account Location**: **API Server URL**

* QualysGuard US platform: qualysapi.qualys.com
* QualysGuard EU platform: qualysapi.qualys.de
* QualysGuard @Customer platform: qualysapi.

To use fetchreport.pl you must identify the report template ID for the automatic scan report you would like to download.  The QualysGuard UI provides this information. Follow the step of the screenshote below to get the report template ID.

![Image](Screen Shot 2011-12-28 at 18.28.46 .png)

The QualysGuard API function “report_template_list.php” provides a list of report template in your account including report template IDs. If your account is on the QualysGuard US platform, you can make a report list request using a URL like this: 

If your account is on another QualysGuard platform, replace the server URL “qualysapi.qualys.com” with the URL for your platform.

The integration is accomplished via Perl script that will reside on a workstation or server system that has access to the internet.  The Perl script can be run with specific parameters and it will log into your QualysGuard account and download the specified report.

Installation and Configuration Process

**Assumptions:**

  * Perl must be installed and running (for Windows we recommend Activeperl, 
  * CPAN is installed and configured for Unix or Linux based systems
  * PPM is installed and configured for Windows systems (installed by default with ActivePerl)

## Perl Module Installation:

[TO BE COMPLETED WITH A LINK TO A GENERIC DOCUMENT EXPLAINING THE PROCESS THAT IS APPLICABLE FOR ALL QUALYS PERL SCRIPTS]

**Open Command Prompt:**

To start the process in Windows, open a command prompt, switch directory to c:\Perl (or wherever Perl is installed).

**Perl Script Installation:**

To view the command line options, enter:

perl fetchreport.pl

The options for running the script will then be displayed as shown below.

![Image](Screen Shot 2011-12-28 at 19.13.03 .png)

	Required Arguments:
	
	  --username=SOMEUSER          QualysGuard username
	
	  --password=SOMEPASS          Password for username
	
	  --reportid=SOMENUMBER        Numeric Report Template ID
	
	  --format=[mht|pdf|html|xml]  Report format
	
	  --path=SOMEPATH              Output directory
	
	  --serverurl=  Platform server url for launching reports. Must start with 
	
	Optional Arguments:
	
	  --proxy=[http://USER:PASS@http://SOMEURL:PORT       HTTPS proxy URL with option USER LOGIN for proxy auth.
	
	  --pdf_password               Password for PDF encrypted reports (can only be used with option --format=pdf)
	
	  --recipient_group            List of groups for PDF encrypted reports (can only be used with option
	
	                               --format=pdf and --pdf_password MUST be set)
	
	  --ag_ids                     List of Asset Groups ID when requesting a REMEDIATION report. Set to 0 for
	
	                               'All'. Make sure the variable All_asset_group_id is properly set in this
	
	                               perl script
	
	  --debug=y                    Outputs additional information
	
	  --debug=yy                   Outputs lots of additional information
	
	  --report_type=[Scan|Remediation]           'Scan' is the default value. For 'Remediation' the default
	
	                               value for 'assignee_type' is 'All' (All users)
	
	  --generate_only=[1|0]        Only generates the report saved in the QualysGuard report share. The
	
	                               report is not downloaded localy. Default is 0
	
	  --report_title=text          default report title is empty unless this option is set
	
	  --authentication=[basic|session]   'basic' is the default and recommended value to avoid any
	
	                               potential expired session issue

Type "perl fetchreport.pl" and specify the correct parameters for your account. This will launch the report with the Report Share functionality.

Sample:

	c:\perl\perl fetchreport.pl --username=username --password=password --reportid=123456 --format=pdf --path=. --serverurl=

While the report is running, you can view the report status in the QualysGuard UI in the Report Share section (select Report on the left menu). When the report completes, the script automatically downloads the report and places it in the specified directory with.

The report will be available in the QualysGuard Report Share until it expires automatically – 7 days after its creation date.
