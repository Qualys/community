This is example scripts for downloading and correlating different report types in Qualysguard API.  It's made up of two main perl scripts and multiple shell scripts (one shell script for every set of 3 reports you wish to correlate).

Before using these scripts you must setupt the set of 3 reports (one Scorecard, One Patch, and One Scan/Vulnerability report) named very carfeully the SAME thing (for example "DataCenter Linux Scorecard Report, DataCenter Linux Patch Report, DataCenter Linux Vuln Report") and using the exact same Asset Groups or Asset Tags.  Otherwise the combiend report will produce data that doesn't match appropriately.

cr.pl
==========

THis script combines the reports downloaded with dlrepots.pl and combines them into a single Excel spreadsheet.  Some processing is done to build Summary and Patch tabs in addition to the raw CSV data from the reports themselves.  Customize this for your environment.

dlreports.pl
===========
Downaods the latest Scorecard, patch, and Vuln report for a given subset of Asset Groups or Tags. 

DataCenter Linux Shell Script (dc_linux.sh)
===========
THis is the shell script you actually execute when you wish to downooad and combine the reports.  YOu should create multiple copies of this shell script changing the $NAME variable to run and download  (sets of 3) you wish to pull and correlate.
