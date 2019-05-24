community
=========

# Important

This directory contains Qualys community open source scripts. The sample code demonstrates the functionality of the QualysGuard API. Several sample scripts are provided to show how to use API features to perform network security audits and vulnerability management.

These scripts are unsupported and are provided as proof-of-concept only.Scripts options and details are availalable via `--help`.

Note, that if you account is setup on a different platform you may need to edit the script and change the FQDN via hard coded variables or via a run time parameter (e.g. `--serverurl=`) from `qualsapi.qualys.com` to one of the following:

Platform                  | URI
------------------------- | -------------------------------------
QualysGuard US Platform 1 | https://qualysapi.qualys.com
QualysGuard US Platform 2 | https://qualysapi.qg2.apps.qualys.com
QualysGuard EU Platform   | https://qualysapi.qualys.eu
QualysGuard @Customer     | https://qualysapi.<customer_base_url>

# Scripts summary

## [about](about)

Returns the version ID strings for the QualysGuard MSP API, the web application, scanner software, and vulnerability signatures.

## [acceptEULA](acceptEULA)

This script demonstrates how to accept the Qualys Service End User License Agreement (EULA) on behalf of a customer.

## [addassetip](addassetip)

This script adds asset IP addresses to a QualysGuard subscription by  importing the assets from a CSV file. 

## [adUserSync](adUserSync)

Performs synchronization (of sorts) with Active Directory.

## [compare](compare)

This script totals the severity levels for vulnerabilities detected by a QualysGuard scan and calculates a total score. This score can be calculated from an existing scan, or from running a scan. This base score is compared to the most recent score for the same IP address range, if one exists, and the difference is reported.

## [cvestats](cvestats)

A script to get a CSV of all the CVEs currently covered in our KB.

## [fetchreport](fetchreport)

Download a QualysGuard report based on a report template.

## [getmap](getmap)

Demonstrates how to interact with the QualysGuard network map functions including: Launch a map, launch a map and save the report on the QualysGuard server, list saved map reports, retrieve a saved map report, list maps in progress, and cancel a running map.

## [getscan](getscan)

Demonstrates how to interact with the QualysGuard scan functions including: Launch a scan, launch a scan and save the report on the QualysGuard server, list saved scan reports, retrieve a saved scan report, list scans in progress, and cancel a running scan. 

## [installedSoftware](installedSoftware)

Generates a list of all installed software in the environment.

## [kbstats](kbstats)

Gets more detailed statistics on the KB, including counts by category, total Bugtraq items, etc.

## [lastScanInfo](lastScanInfo)

Gets the last scan time and scanner for the specified IP.

## [notScannedSince](notScannedSince)

Find all assets not scanned within a number of days specified and add them to a group.

## [numhop_v3](numhop_v3)

Gets traceroute information for specified asset groups and timeframe and calculates useful stats.

## [pcidl](pcidl)

Downloads the QID, name, and CVSS base score of all PCI vulnerabilities in the KB (those that will cause a PCI failure).

## [portReport](portReport)

A poor man's "Open Ports and Services" report.

## [purgeUnscannedHosts](purgeUnscannedHosts)
Purges the automatic data for all hosts not scanned since a particular date/in XX days.

## [scanner_details](scanner_details)

Output the complete scanner details as they are available in the GUI.

## [scanoptions](scanoptions)

This script demonstrates how to interact with scan service options. The following options may be set: Scan dead hosts, ports to scan, and scan hosts behind a load balancer. 

## [scanStats](scanStats)

Downloads scheduled tasks and look for sub-optimal scanner loads.

## [scanTimesv2](scanTimesv2)

A script to parse the results of QID 45038 (Host Scan Time) and calculate the average scan time. It will also call out the IP and OS of systems that take abnormally long.

## [scheduledscans](scheduledscans)

This script demonstrates how to define scan or map tasks to occur on a regular basis -- daily, weekly, or monthly. 

## [score](score)

This script, like vulnsummary, demonstrates how to connect to the QualysGuard API, and how to extract and display data from the scan report XML document.

## [Ticket Notification Engine (TNE)](tne)

Qualys provides a Ticket Notification Engine (TNE) that outputs SMTP messages based on XML versions of individual tickets in QualysGuard that are consumable by Remedy ticketing systems. The TNE can also be configured to support some customization to support the receiving ticketing system.

## [usercreate](usercreate)

This script adds user accounts to an existing subscription by importing user account information from a user-defined CSV file.

## [vulnsummary](vulnsummary)

This script demonstrates how to connect to the QualysGuard API and how to extract vulnerability data from the scan report XML document.
