# scheduledscans

This script demonstrates how to define scan or map tasks to occur on a regular basis — daily, weekly, or monthly.

When executed, it displays the results of interacting with the QualysGuard task scheduling features including: Set scheduled tasks, list scheduled tasks, and delete scheduled tasks.

The script also shows how to extract the current list of scheduled tasks from the returned XML document upon success. For each scheduled task the following information is displayed: Task status, reference code, title, target IP address or range, and the date and time when the task will next be launched.

Note: This script takes a username and password as the first two command line arguments.

# Dependencies For Perl

Perl versions 5.6.0 and greater are supported. 

This script relies on several freely available modules from CPAN. You will need to have the following installed:

  * Bundle::LWP — Basic WWW library
  * Net::SSL — SSL support
      * Requires OpenSSL
  * XML::Twig — Handy XML manipulation
      * Requires James Clark's expat and XML::Expat

# Legal

QualysGuard(R) MSP API Sample Code README

@(#)$Revision: 1.13 $

Copyright 2007 by Qualys, Inc. All Rights Reserved.

http://www.qualys.com