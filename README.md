community
=========

# Important

Qualys community open source scripts.

These scripts are unsupported and are provided as proof-of-concept only.Scripts options and details are availalable via `--help`.

Note, that if you account is setup on a different platform you may need to edit the script and change the FQDN via hard coded variables or via a run time parameter (e.g. `--serverurl=`) from `qualsapi.qualys.com` to one of the following:

Platform                  | URI
------------------------- | -------------------------------------
QualysGuard US Platform 1 | https://qualysapi.qualys.com
QualysGuard US Platform 2 | https://qualysapi.qg2.apps.qualys.com
QualysGuard EU Platform   | https://qualysapi.qualys.eu
QualysGuard @Customer     | https://qualysapi.<customer_base_url>

# about

Returns the version ID strings for the QualysGuard MSP API, the web application, scanner software, and vulnerability signatures.

# acceptEULA

This script demonstrates how to accept the Qualys Service End User License Agreement (EULA) on behalf of a customer.
 
# addassetip

This script adds asset IP addresses to a QualysGuard subscription by  importing the assets from a CSV file. 
 
# compare

This script totals the severity levels for vulnerabilities detected by a QualysGuard scan and calculates a total score. This score can be calculated from an existing scan, or from running a scan. This base score is compared to the most recent score for the same IP address range, if one exists, and the difference is reported.
 
# fetchreport

The fetchreport script can be run on any system utilizing Perl and will download a QualysGuard report based on a report template.
 
# getmap

This script demonstrates how to interact with the QualysGuard network map functions including: Launch a map, launch a map and save the report on the QualysGuard server, list saved map reports, retrieve a saved map report, list maps in progress, and cancel a running map.
 
# getscan

This script demonstrates how to interact with the QualysGuard scan functions including: Launch a scan, launch a scan and save the report on the QualysGuard server, list saved scan reports, retrieve a saved scan report, list scans in progress, and cancel a running scan. 
 
# scanoptions

This script demonstrates how to interact with scan service options. The following options may be set: Scan dead hosts, ports to scan, and scan hosts behind a load balancer. 

# scheduledscans

This script demonstrates how to define scan or map tasks to occur on a regular basis -- daily, weekly, or monthly. 
 
# score

This script, like vulnsummary, demonstrates how to connect to the QualysGuard API, and how to extract and display data from the scan report XML document.
 
# Ticket Notification Engine (TNE)

Qualys provides a Ticket Notification Engine (TNE) that outputs SMTP messages based on XML versions of individual tickets in QualysGuard that are consumable by Remedy ticketing systems. The TNE can also be configured to support some customization to support the receiving ticketing system.
 
# usercreate

This script adds user accounts to an existing subscription by importing user account information from a user-defined CSV file.
 
# vulnsummary

This script demonstrates how to connect to the QualysGuard API and how to extract vulnerability data from the scan report XML document.
